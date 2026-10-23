// Original read-only inventory tool; no game code is included or executed.
// Format references:
// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
// https://www.source2.wiki/FileFormats/vpk
#include <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <charconv>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

namespace lab {
using Bytes = std::vector<std::uint8_t>;
constexpr std::uint64_t pe_budget = 256ULL * 1024 * 1024;
constexpr std::uint64_t tree_budget = 32ULL * 1024 * 1024;
constexpr std::size_t string_budget = 4096;
constexpr std::size_t entry_budget = 1000000;
constexpr std::string_view version = "0.1.0";

[[noreturn]] void fail(const std::string& message) { throw std::runtime_error(message); }

void bounds(std::uint64_t offset, std::uint64_t length, std::uint64_t size,
            std::string_view field) {
    if (offset > size || length > size - offset) {
        fail("truncated or out-of-bounds " + std::string(field));
    }
}

std::uint16_t u16(const Bytes& bytes, std::uint64_t offset) {
    bounds(offset, 2, bytes.size(), "uint16");
    return std::uint16_t(bytes[offset]) | std::uint16_t(bytes[offset + 1]) << 8;
}

std::uint32_t u32(const Bytes& bytes, std::uint64_t offset) {
    bounds(offset, 4, bytes.size(), "uint32");
    return std::uint32_t(bytes[offset]) | std::uint32_t(bytes[offset + 1]) << 8 |
           std::uint32_t(bytes[offset + 2]) << 16 | std::uint32_t(bytes[offset + 3]) << 24;
}

std::string json(std::string_view text) {
    std::ostringstream out;
    out << '"';
    for (unsigned char character : text) {
        if (character == '"' || character == '\\') out << '\\' << character;
        else if (character < 0x20) {
            out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                << unsigned(character) << std::dec;
        } else out << character;
    }
    out << '"';
    return out.str();
}

void validate_utf8(std::string_view text) {
    for (std::size_t i = 0; i < text.size();) {
        unsigned char first = text[i++];
        if (first < 0x80) {
            if (first < 0x20 || first == 0x7f) fail("control byte in directory string");
            continue;
        }
        unsigned count;
        std::uint32_t value;
        std::uint32_t minimum;
        if (first >= 0xc2 && first <= 0xdf) { count = 1; value = first & 0x1f; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { count = 2; value = first & 0x0f; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { count = 3; value = first & 0x07; minimum = 0x10000; }
        else fail("invalid UTF-8 directory string");
        if (count > text.size() - i) fail("truncated UTF-8 directory string");
        for (unsigned n = 0; n < count; ++n) {
            unsigned char next = text[i++];
            if ((next & 0xc0) != 0x80) fail("invalid UTF-8 directory string");
            value = (value << 6) | (next & 0x3f);
        }
        if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) {
            fail("invalid UTF-8 directory string");
        }
    }
}

std::string sha256(const Bytes& bytes) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.data(), static_cast<CC_LONG>(bytes.size()), digest);
    std::ostringstream out;
    for (unsigned char byte : digest) out << std::hex << std::setw(2) << std::setfill('0') << unsigned(byte);
    return out.str();
}

class File {
    int descriptor_ = -1;
    struct stat initial_{};
public:
    explicit File(const std::filesystem::path& path) {
        descriptor_ = ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NONBLOCK);
        if (descriptor_ < 0) fail("cannot open input: " + std::string(std::strerror(errno)));
        if (::fstat(descriptor_, &initial_) || !S_ISREG(initial_.st_mode) || initial_.st_size < 0) {
            ::close(descriptor_);
            descriptor_ = -1;
            fail("input must be a readable regular file");
        }
    }
    File(const File&) = delete;
    File& operator=(const File&) = delete;
    ~File() { if (descriptor_ >= 0) ::close(descriptor_); }
    std::uint64_t size() const { return static_cast<std::uint64_t>(initial_.st_size); }
    Bytes read(std::uint64_t offset, std::uint64_t length) const {
        bounds(offset, length, size(), "file read");
        Bytes result(static_cast<std::size_t>(length));
        std::size_t done = 0;
        while (done < result.size()) {
            auto received = ::pread(descriptor_, result.data() + done, result.size() - done,
                                    static_cast<off_t>(offset + done));
            if (received < 0 && errno == EINTR) continue;
            if (received <= 0) fail("input changed or became unreadable during read");
            done += static_cast<std::size_t>(received);
        }
        return result;
    }
    void verify_unchanged() const {
        struct stat current{};
        if (::fstat(descriptor_, &current) || current.st_size != initial_.st_size ||
            current.st_mtimespec.tv_sec != initial_.st_mtimespec.tv_sec ||
            current.st_mtimespec.tv_nsec != initial_.st_mtimespec.tv_nsec ||
            current.st_ctimespec.tv_sec != initial_.st_ctimespec.tv_sec ||
            current.st_ctimespec.tv_nsec != initial_.st_ctimespec.tv_nsec) {
            fail("input changed during inspection");
        }
    }
};

std::string host_architecture() {
#if defined(__arm64__) || defined(__aarch64__)
    return "arm64";
#else
    return "other";
#endif
}

std::string prefix(std::string_view operation, const std::filesystem::path& path) {
    return "{\"tool\":\"cs2-native-lab\",\"version\":" + json(version) +
        ",\"kind\":\"research-tool\",\"game_runtime\":false,\"operation\":" + json(operation) +
        ",\"host_architecture\":" + json(host_architecture()) +
        ",\"input\":" + json(path.string());
}

struct Section { std::uint32_t virtual_address, virtual_size, raw_offset, raw_size; };

std::string inspect_pe(const std::filesystem::path& path) {
    File file(path);
    if (file.size() > pe_budget) fail("PE file exceeds explicit 256 MiB inspection budget");
    const Bytes bytes = file.read(0, file.size());
    bounds(0, 64, bytes.size(), "DOS header");
    if (u16(bytes, 0) != 0x5a4d) fail("not a DOS MZ/PE image");
    const std::uint64_t pe = u32(bytes, 0x3c);
    if (pe < 64) fail("PE header overlaps DOS header");
    bounds(pe, 24, bytes.size(), "PE signature and COFF header");
    if (u32(bytes, pe) != 0x00004550) fail("invalid PE signature");
    const auto machine = u16(bytes, pe + 4);
    const auto section_count = u16(bytes, pe + 6);
    if (section_count == 0 || section_count > 96) fail("unsupported PE section count (1..96 required)");
    const auto optional_size = u16(bytes, pe + 20);
    const auto characteristics = u16(bytes, pe + 22);
    const std::uint64_t optional = pe + 24;
    bounds(optional, optional_size, bytes.size(), "optional header");
    if (optional_size < 2) fail("missing PE optional header");
    const auto magic = u16(bytes, optional);
    if (magic != 0x10b && magic != 0x20b) fail("unsupported PE optional-header magic");
    const bool plus = magic == 0x20b;
    const std::uint64_t directories_offset = plus ? 112 : 96;
    if (optional_size < directories_offset) fail("truncated PE optional header");
    const auto directory_count = u32(bytes, optional + (plus ? 108 : 92));
    if (directory_count > (optional_size - directories_offset) / 8) {
        fail("PE data directories extend beyond optional header");
    }
    const auto header_size = u32(bytes, optional + 60);
    const std::uint64_t table = optional + optional_size;
    bounds(table, std::uint64_t(section_count) * 40, bytes.size(), "section table");
    if (header_size < table + std::uint64_t(section_count) * 40 || header_size > bytes.size()) {
        fail("invalid PE SizeOfHeaders");
    }
    std::vector<Section> sections;
    for (unsigned i = 0; i < section_count; ++i) {
        const auto at = table + i * 40;
        Section section{u32(bytes, at + 12), u32(bytes, at + 8),
                        u32(bytes, at + 20), u32(bytes, at + 16)};
        bounds(section.raw_offset, section.raw_size, bytes.size(), "section raw data");
        if (std::uint64_t(section.virtual_address) + std::max(section.virtual_size, section.raw_size) >
            (1ULL << 32)) fail("PE section virtual range overflows");
        sections.push_back(section);
    }
    auto rva_offset = [&](std::uint64_t rva, std::uint64_t length) -> std::uint64_t {
        bounds(rva, length, 1ULL << 32, "PE RVA");
        std::vector<std::uint64_t> matches;
        if (rva < header_size && length <= header_size - rva) matches.push_back(rva);
        for (const auto& section : sections) {
            if (rva >= section.virtual_address) {
                const auto delta = rva - section.virtual_address;
                if (delta < section.raw_size && length <= section.raw_size - delta) {
                    matches.push_back(std::uint64_t(section.raw_offset) + delta);
                }
            }
        }
        if (matches.size() != 1) fail("unmapped or ambiguous PE RVA");
        bounds(matches.front(), length, bytes.size(), "mapped PE RVA");
        return matches.front();
    };
    std::vector<std::string> imports;
    if (directory_count > 1) {
        const auto import_rva = u32(bytes, optional + directories_offset + 8);
        const auto import_size = u32(bytes, optional + directories_offset + 12);
        if ((import_rva == 0) != (import_size == 0)) fail("inconsistent PE import directory");
        if (import_rva != 0) {
            if (import_size < 20 || import_size > 8 * 1024 * 1024) fail("invalid PE import-directory size");
            bounds(import_rva, import_size, 1ULL << 32, "import directory RVA range");
            (void)rva_offset(import_rva, import_size);
            bool terminated = false;
            for (std::uint64_t index = 0; index < 8192; ++index) {
                const auto delta = index * 20;
                if (delta + 20 > import_size) break;
                const auto at = rva_offset(std::uint64_t(import_rva) + delta, 20);
                bool zero = true;
                for (unsigned word = 0; word < 5; ++word) zero = zero && u32(bytes, at + word * 4) == 0;
                if (zero) { terminated = true; break; }
                const std::uint64_t name_rva = u32(bytes, at + 12);
                if (!name_rva) fail("PE import descriptor has an empty name RVA");
                std::string name;
                bool end = false;
                for (std::uint64_t n = 0; n <= string_budget; ++n) {
                    if (n == string_budget) fail("PE import name exceeds 4096-byte budget");
                    auto character = bytes[rva_offset(name_rva + n, 1)];
                    if (character == 0) { end = true; break; }
                    if (character < 0x20 || character > 0x7e) fail("unsupported non-ASCII PE import name");
                    name.push_back(static_cast<char>(character));
                }
                if (!end || name.empty()) fail("unterminated or empty PE import name");
                imports.push_back(name);
            }
            if (!terminated) fail("unterminated PE import descriptor table or descriptor budget exceeded");
        }
    }
    file.verify_unchanged();
    std::string architecture = "unknown";
    if (machine == 0x8664) architecture = "x86_64";
    else if (machine == 0x14c) architecture = "x86";
    else if (machine == 0xaa64) architecture = "arm64";
    else if (machine == 0xa641) architecture = "arm64ec";
    else if (machine == 0xa64e) architecture = "arm64x";
    std::ostringstream out;
    out << prefix("inspect-pe", path) << ",\"format\":" << json(plus ? "PE32+" : "PE32")
        << ",\"target_platform\":\"windows\",\"target_architecture\":" << json(architecture)
        << ",\"machine\":" << machine << ",\"file_size\":" << file.size()
        << ",\"section_count\":" << section_count
        << ",\"is_dll\":" << ((characteristics & 0x2000) ? "true" : "false")
        << ",\"entry_point_rva\":" << u32(bytes, optional + 16)
        << ",\"sha256\":" << json(sha256(bytes))
        << ",\"identity_scope\":\"complete-input-file\",\"inspection_budget_bytes\":" << pe_budget
        << ",\"imported_dlls\":[";
    for (std::size_t i = 0; i < imports.size(); ++i) out << (i ? "," : "") << json(imports[i]);
    out << "],\"limitations\":[\"DLL inventory covers the normal import directory only; delay imports and dynamically loaded modules remain unknown.\","
           "\"Static metadata does not establish execution or compatibility; this tool is not a game runtime.\","
           "\"The SHA-256 identifies bytes read, not publisher authenticity or a verified signature.\"]}";
    return out.str();
}

class TreeReader {
    const Bytes& bytes_;
public:
    std::size_t position = 0;
    explicit TreeReader(const Bytes& bytes) : bytes_(bytes) {}
    std::string text() {
        const auto start = position;
        while (position < bytes_.size() && bytes_[position] != 0) {
            if (position - start >= string_budget) fail("VPK tree string exceeds 4096-byte budget");
            ++position;
        }
        if (position == bytes_.size()) fail("unterminated VPK directory string");
        std::string value(bytes_.begin() + start, bytes_.begin() + position);
        ++position;
        validate_utf8(value);
        return value;
    }
    std::uint16_t number16() { auto result = u16(bytes_, position); position += 2; return result; }
    std::uint32_t number32() { auto result = u32(bytes_, position); position += 4; return result; }
    void skip(std::size_t amount) {
        bounds(position, amount, bytes_.size(), "VPK preload data");
        position += amount;
    }
};

void component(std::string_view value) {
    if (value.empty() || value == "." || value == ".." ||
        value.find_first_of("/\\:") != std::string_view::npos) {
        fail("unsafe VPK path component");
    }
}

void directory(std::string_view value) {
    if (value == " ") return;
    if (value.empty() || value.front() == '/' || value.find_first_of("\\:") != std::string_view::npos) {
        fail("unsafe VPK directory path");
    }
    std::size_t offset = 0;
    while (true) {
        const auto next = value.find('/', offset);
        component(value.substr(offset, next == std::string_view::npos ? next : next - offset));
        if (next == std::string_view::npos) break;
        offset = next + 1;
    }
}

struct Entry {
    std::string path;
    std::uint32_t crc, offset, length;
    std::uint16_t preload, archive;
};

std::string inspect_vpk(const std::filesystem::path& path, std::size_t limit, std::string_view filter) {
    File file(path);
    const auto first = file.read(0, 12);
    if (u32(first, 0) != 0x55aa1234) fail("invalid VPK signature");
    const auto vpk_version = u32(first, 4);
    if (vpk_version != 1 && vpk_version != 2) fail("unsupported VPK version (only 1 and 2)");
    const auto tree_size = u32(first, 8);
    if (tree_size == 0 || tree_size > tree_budget) fail("VPK tree exceeds 32 MiB budget or has no terminator");
    const std::uint64_t header_size = vpk_version == 1 ? 12 : 28;
    Bytes header = first;
    if (vpk_version == 2) {
        const auto remainder = file.read(12, 16);
        header.insert(header.end(), remainder.begin(), remainder.end());
    }
    bounds(header_size, tree_size, file.size(), "VPK directory tree");
    const std::uint64_t data_start = header_size + tree_size;
    const std::uint64_t data_size = vpk_version == 2 ? u32(header, 12) : file.size() - data_start;
    std::uint64_t declared_end = data_start + data_size;
    if (vpk_version == 2) declared_end += std::uint64_t(u32(header, 16)) + u32(header, 20) + u32(header, 24);
    if (declared_end > file.size()) fail("truncated VPK data or trailer sections");
    const auto tree = file.read(header_size, tree_size);
    Bytes header_and_tree = header;
    header_and_tree.insert(header_and_tree.end(), tree.begin(), tree.end());
    TreeReader reader(tree);
    std::map<std::string, std::uint64_t> extensions;
    std::map<std::uint16_t, std::uint64_t> archives;
    std::unordered_set<std::string> paths;
    std::vector<Entry> selected;
    std::uint64_t entries = 0, matched = 0, total_preload = 0, total_bytes = 0;
    while (true) {
        const auto extension = reader.text();
        if (extension.empty()) break;
        if (extension != " ") component(extension);
        while (true) {
            const auto parent = reader.text();
            if (parent.empty()) break;
            directory(parent);
            while (true) {
                const auto name = reader.text();
                if (name.empty()) break;
                component(name);
                Entry entry;
                entry.path = (parent == " " ? "" : parent + "/") + name +
                             (extension == " " ? "" : "." + extension);
                if (entry.path.size() > string_budget) fail("reconstructed VPK path exceeds 4096-byte budget");
                if (!paths.insert(entry.path).second) fail("duplicate VPK entry path");
                entry.crc = reader.number32();
                entry.preload = reader.number16();
                entry.archive = reader.number16();
                entry.offset = reader.number32();
                entry.length = reader.number32();
                if (reader.number16() != 0xffff) fail("invalid VPK entry terminator");
                if (entry.archive > 0x7fff) fail("invalid VPK archive index");
                reader.skip(entry.preload);
                if (entry.archive == 0x7fff && entry.length != 0) {
                    bounds(entry.offset, entry.length, data_size, "embedded VPK entry data");
                } else if (std::uint64_t(entry.offset) + entry.length > (1ULL << 32)) {
                    fail("external VPK entry range exceeds 32-bit archive address space");
                }
                if (++entries > entry_budget) fail("VPK entry budget exceeded");
                ++extensions[extension == " " ? "(none)" : extension];
                ++archives[entry.archive];
                total_preload += entry.preload;
                total_bytes += std::uint64_t(entry.preload) + entry.length;
                if (entry.path.find(filter) != std::string::npos) {
                    ++matched;
                    if (selected.size() < limit) selected.push_back(std::move(entry));
                }
            }
        }
    }
    if (reader.position != tree.size()) fail("unexpected bytes after VPK tree terminator");
    file.verify_unchanged();
    std::ostringstream out;
    out << prefix("inspect-vpk", path) << ",\"format\":\"VPK\",\"vpk_version\":" << vpk_version
        << ",\"file_size\":" << file.size() << ",\"header_size\":" << header_size
        << ",\"tree_size\":" << tree_size << ",\"tree_budget_bytes\":" << tree_budget
        << ",\"bytes_read\":" << header_size + tree_size
        << ",\"sha256_header_and_tree\":" << json(sha256(header_and_tree))
        << ",\"identity_scope\":\"header-and-tree-only\",\"file_data_section_size\":" << data_size
        << ",\"archive_hash_section_size\":" << (vpk_version == 2 ? u32(header, 16) : 0)
        << ",\"other_md5_section_size\":" << (vpk_version == 2 ? u32(header, 20) : 0)
        << ",\"signature_section_size\":" << (vpk_version == 2 ? u32(header, 24) : 0)
        << ",\"string_budget_bytes\":" << string_budget << ",\"entry_budget\":" << entry_budget
        << ",\"uninspected_trailing_bytes\":" << file.size() - declared_end
        << ",\"total_entries\":" << entries << ",\"matched_entries\":" << matched
        << ",\"listed_entries\":" << selected.size()
        << ",\"listing_truncated\":" << (matched > selected.size() ? "true" : "false")
        << ",\"filter\":" << json(filter) << ",\"limit\":" << limit
        << ",\"total_preload_bytes\":" << total_preload
        << ",\"declared_entry_content_bytes\":" << total_bytes << ",\"extensions\":{";
    bool separator = false;
    for (const auto& [extension, count] : extensions) {
        out << (separator ? "," : "") << json(extension) << ':' << count; separator = true;
    }
    out << "},\"archive_references\":[";
    separator = false;
    for (const auto& [archive, count] : archives) {
        out << (separator ? "," : "") << "{\"archive_index\":" << archive
            << ",\"embedded\":" << (archive == 0x7fff ? "true" : "false")
            << ",\"entry_count\":" << count << '}'; separator = true;
    }
    out << "],\"entries\":[";
    for (std::size_t i = 0; i < selected.size(); ++i) {
        const auto& entry = selected[i];
        out << (i ? "," : "") << "{\"path\":" << json(entry.path) << ",\"crc32\":" << entry.crc
            << ",\"preload_bytes\":" << entry.preload << ",\"archive_index\":" << entry.archive
            << ",\"data_offset\":" << entry.offset << ",\"data_length\":" << entry.length
            << ",\"total_length\":" << std::uint64_t(entry.preload) + entry.length << '}';
    }
    out << "],\"limitations\":[\"Only the header and directory tree are read and hashed; no external archives or bulk asset data are opened.\","
           "\"CRC32 values and trailer section sizes are metadata; archive hashes and signatures are not read or verified.\","
           "\"External archive ranges are not checked against archive files; content availability remains unknown.\","
           "\"For zero-length payloads, data_offset is preserved metadata with no readable-range meaning; sentinel offsets are allowed.\","
           "\"VPK version 2 signatures may carry bytes beyond the declared descriptor; trailing bytes remain uninspected.\","
           "\"This is a research inventory tool, not CS2 or a Source 2 engine.\"]}";
    return out.str();
}

std::size_t parse_limit(std::string_view value) {
    std::size_t result = 0;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), result);
    if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size() || result > 1000) {
        fail("--limit must be an integer from 0 to 1000");
    }
    return result;
}

int run(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "--version") {
        std::cout << "{\"tool\":\"cs2-native-lab\",\"version\":" << json(version)
                  << ",\"kind\":\"research-tool\",\"host_architecture\":" << json(host_architecture())
                  << ",\"game_runtime\":false}\n";
        return 0;
    }
    if (argc < 2 || (argc == 2 && std::string_view(argv[1]) == "--help")) {
        std::cout << "cs2-native-lab: read-only research inventory (not a game runtime)\n"
                     "  inspect-pe <path>\n"
                     "  inspect-vpk <path> [--limit N] [--filter text]\n"
                     "Budgets: PE 256 MiB; VPK tree 32 MiB; strings 4096 bytes; listing 0..1000.\n";
        return argc < 2 ? 2 : 0;
    }
    if (argc < 3) fail("missing input path");
    const std::string_view command(argv[1]);
    if (command == "inspect-pe") {
        if (argc != 3) fail("inspect-pe accepts exactly one input path");
        std::cout << inspect_pe(argv[2]) << '\n';
    } else if (command == "inspect-vpk") {
        std::size_t limit = 20;
        std::string_view filter;
        bool limit_seen = false, filter_seen = false;
        for (int i = 3; i < argc; i += 2) {
            if (i + 1 >= argc) fail("missing option value");
            const std::string_view option(argv[i]);
            if (option == "--limit" && !limit_seen) { limit = parse_limit(argv[i + 1]); limit_seen = true; }
            else if (option == "--filter" && !filter_seen) { filter = argv[i + 1]; filter_seen = true; }
            else fail("unknown or duplicate option");
        }
        validate_utf8(filter);
        std::cout << inspect_vpk(argv[2], limit, filter) << '\n';
    } else fail("unknown command");
    return 0;
}
} // namespace lab

int main(int argc, char** argv) {
    try { return lab::run(argc, argv); }
    catch (const std::exception& error) {
        std::cerr << "{\"tool\":\"cs2-native-lab\",\"kind\":\"research-tool\",\"game_runtime\":false,"
                     "\"error\":" << lab::json(error.what()) << "}\n";
        return 2;
    }
}
