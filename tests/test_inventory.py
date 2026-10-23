"""Synthetic fixtures follow the published PE and VPK format descriptions.

No Valve executable, game asset, extracted resource or proprietary source is
stored in this repository. Tests call the compiled native CLI as a black box.
"""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


BINARY = Path(os.environ.get("CS2_NATIVE_LAB", ".build/cs2-native-lab")).resolve()


def pe_image(*, plus=True, imports=True, machine=None):
    image = bytearray(0x400)
    image[0:2] = b"MZ"
    struct.pack_into("<I", image, 0x3C, 0x80)
    image[0x80:0x84] = b"PE\0\0"
    optional_size = 240 if plus else 224
    struct.pack_into("<HHIIIHH", image, 0x84,
                     machine if machine is not None else (0x8664 if plus else 0x14C),
                     1, 0, 0, 0, optional_size, 0x22)
    optional = 0x98
    struct.pack_into("<H", image, optional, 0x20B if plus else 0x10B)
    struct.pack_into("<I", image, optional + 16, 0x1100)
    struct.pack_into("<II", image, optional + 56, 0x2000, 0x200)
    struct.pack_into("<I", image, optional + (108 if plus else 92), 16)
    section = optional + optional_size
    image[section:section + 8] = b".rdata\0\0"
    struct.pack_into("<IIII", image, section + 8, 0x200, 0x1000, 0x200, 0x200)
    if imports:
        directories = optional + (112 if plus else 96)
        struct.pack_into("<II", image, directories + 8, 0x1000, 40)
        struct.pack_into("<IIIII", image, 0x200, 0x1080, 0, 0, 0x1050, 0x1090)
        image[0x250:0x25D] = b"KERNEL32.dll\0"
    return image


def vpk_tree(entries):
    """Each tuple is extension, directory, basename, optional entry properties."""
    grouped = {}
    for extension, directory, name, fields in entries:
        grouped.setdefault(extension, {}).setdefault(directory, []).append((name, fields))
    tree = bytearray()
    for extension, directories in grouped.items():
        tree += extension.encode("utf8") + b"\0"
        for directory, files in directories.items():
            tree += directory.encode("utf8") + b"\0"
            for name, fields in files:
                preload = fields.get("preload", b"")
                tree += name.encode("utf8") + b"\0"
                tree += struct.pack("<IHHIIH", fields.get("crc", 0x12345678),
                                    fields.get("preload_size", len(preload)),
                                    fields.get("archive", 0),
                                    fields.get("offset", 12),
                                    fields.get("length", 4),
                                    fields.get("terminator", 0xFFFF))
                tree += preload
            tree += b"\0"
        tree += b"\0"
    tree += b"\0"
    return tree


def vpk_image(entries=(), *, version=2, data=b"", trailer=b"", section_sizes=None):
    tree = vpk_tree(entries)
    header = struct.pack("<III", 0x55AA1234, version, len(tree))
    if version == 2:
        lengths = section_sizes or (len(data), 0, 0, len(trailer))
        header += struct.pack("<IIII", *lengths)
    return header + tree + data + trailer


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(self, command, contents, *options, valid=True):
        path = self.root / ("sample.exe" if command == "inspect-pe" else "pak01_dir.vpk")
        path.write_bytes(contents)
        process = subprocess.run([str(BINARY), command, str(path), *options],
                                 capture_output=True, text=True, timeout=10)
        if valid:
            self.assertEqual(process.returncode, 0, process.stderr)
            self.assertFalse(process.stderr, process.stderr)
            result = json.loads(process.stdout)
            self.assertEqual(result["kind"], "research-tool")
            self.assertFalse(result["game_runtime"])
            self.assertEqual(result["host_architecture"], "arm64")
            return result
        self.assertEqual(process.returncode, 2, process.stdout)
        self.assertFalse(process.stdout)
        result = json.loads(process.stderr)
        self.assertIn("error", result)
        return result["error"]

    def test_pe32_plus_imports_and_full_identity(self):
        image = pe_image()
        result = self.invoke("inspect-pe", image)
        self.assertEqual(result["format"], "PE32+")
        self.assertEqual(result["target_architecture"], "x86_64")
        self.assertEqual(result["target_platform"], "windows")
        self.assertEqual(result["imported_dlls"], ["KERNEL32.dll"])
        self.assertEqual(result["sha256"], hashlib.sha256(image).hexdigest())
        self.assertEqual(result["identity_scope"], "complete-input-file")

    def test_pe32_without_imports(self):
        result = self.invoke("inspect-pe", pe_image(plus=False, imports=False))
        self.assertEqual(result["format"], "PE32")
        self.assertEqual(result["target_architecture"], "x86")
        self.assertEqual(result["imported_dlls"], [])

    def test_arm64_pe_is_still_windows_not_macos(self):
        result = self.invoke("inspect-pe", pe_image(machine=0xAA64))
        self.assertEqual(result["target_architecture"], "arm64")
        self.assertEqual(result["target_platform"], "windows")

    def test_fifo_inputs_are_rejected_without_waiting_for_a_writer(self):
        path = self.root / "input-fifo"
        os.mkfifo(path)
        for command in ("inspect-pe", "inspect-vpk"):
            with self.subTest(command=command):
                process = subprocess.run([str(BINARY), command, str(path)],
                                         capture_output=True, text=True, timeout=2)
                self.assertEqual(process.returncode, 2)
                self.assertFalse(process.stdout)
                self.assertIn("regular file", json.loads(process.stderr)["error"])

    def test_pe_rejects_truncated_headers(self):
        for length in (0, 1, 63, 0x90, 0x100, 0x199):
            with self.subTest(length=length):
                self.invoke("inspect-pe", pe_image()[:length], valid=False)

    def test_pe_rejects_wrong_signature_or_excessive_sections(self):
        image = pe_image()
        image[0x80:0x84] = b"ELF\0"
        self.assertIn("signature", self.invoke("inspect-pe", image, valid=False))
        image = pe_image()
        struct.pack_into("<H", image, 0x86, 97)
        self.assertIn("section count", self.invoke("inspect-pe", image, valid=False))

    def test_pe_rejects_oversized_data_directory_claim(self):
        image = pe_image()
        struct.pack_into("<I", image, 0x98 + 108, 17)
        self.assertIn("optional header", self.invoke("inspect-pe", image, valid=False))

    def test_pe_rejects_unmapped_import_name(self):
        image = pe_image()
        struct.pack_into("<I", image, 0x20C, 0x70000000)
        self.assertIn("RVA", self.invoke("inspect-pe", image, valid=False))

    def test_pe_requires_null_import_descriptor(self):
        image = pe_image()
        struct.pack_into("<I", image, 0x98 + 112 + 12, 20)
        self.assertIn("unterminated", self.invoke("inspect-pe", image, valid=False))

    def test_pe_rejects_section_file_overflow(self):
        image = pe_image()
        struct.pack_into("<I", image, 0x98 + 240 + 20, 0xFFFFFF00)
        self.assertIn("section raw data", self.invoke("inspect-pe", image, valid=False))

    def test_pe_rejects_inconsistent_import_directory(self):
        image = pe_image()
        struct.pack_into("<I", image, 0x98 + 112 + 12, 0)
        self.assertIn("inconsistent", self.invoke("inspect-pe", image, valid=False))

    def test_pe_rejects_declared_import_range_beyond_section(self):
        image = pe_image()
        struct.pack_into("<I", image, 0x98 + 112 + 12, 0x300)
        self.assertIn("RVA", self.invoke("inspect-pe", image, valid=False))

    def test_pe_size_budget_is_checked_before_read(self):
        path = self.root / "sparse.exe"
        with path.open("wb") as output:
            output.truncate(256 * 1024 * 1024 + 1)
        process = subprocess.run([str(BINARY), "inspect-pe", str(path)],
                                 capture_output=True, text=True, timeout=10)
        self.assertEqual(process.returncode, 2)
        self.assertIn("budget", json.loads(process.stderr)["error"])

    def test_vpk_v1_root_without_extension_and_preload(self):
        image = vpk_image([(" ", " ", "README", {"preload": b"abc", "archive": 0x7FFF,
                                                "offset": 0, "length": 0})], version=1)
        result = self.invoke("inspect-vpk", image)
        self.assertEqual(result["vpk_version"], 1)
        self.assertEqual(result["entries"][0]["path"], "README")
        self.assertEqual(result["total_preload_bytes"], 3)
        self.assertEqual(result["declared_entry_content_bytes"], 3)
        self.assertEqual(result["extensions"], {"(none)": 1})

    def test_vpk_v2_embedded_ranges(self):
        image = vpk_image([("txt", "cfg", "test", {"archive": 0x7FFF, "offset": 1,
                                                   "length": 3})], data=b"xabc")
        result = self.invoke("inspect-vpk", image)
        self.assertEqual(result["entries"][0]["path"], "cfg/test.txt")
        self.assertEqual(result["archive_references"],
                         [{"archive_index": 32767, "embedded": True, "entry_count": 1}])
        self.assertEqual(result["file_data_section_size"], 4)
        self.assertEqual(result["bytes_read"], result["header_size"] + result["tree_size"])
        prefix_size = result["header_size"] + result["tree_size"]
        self.assertEqual(result["sha256_header_and_tree"],
                         hashlib.sha256(image[:prefix_size]).hexdigest())

    def test_vpk_filters_and_limits_do_not_change_inventory_totals(self):
        entries = [("vtex_c", "materials", "stone", {"archive": 0}),
                   ("vmdl_c", "models", "stone", {"archive": 1}),
                   ("vmdl_c", "models", "wood", {"archive": 1})]
        result = self.invoke("inspect-vpk", vpk_image(entries), "--limit", "1",
                             "--filter", "stone")
        self.assertEqual(result["total_entries"], 3)
        self.assertEqual(result["matched_entries"], 2)
        self.assertEqual(result["listed_entries"], 1)
        self.assertTrue(result["listing_truncated"])
        self.assertEqual(result["extensions"], {"vmdl_c": 2, "vtex_c": 1})
        self.assertEqual(len(result["archive_references"]), 2)
        zero = self.invoke("inspect-vpk", vpk_image(entries), "--limit", "0")
        self.assertEqual(zero["entries"], [])
        self.assertEqual(zero["matched_entries"], 3)

    def test_vpk_valid_utf8_names(self):
        result = self.invoke("inspect-vpk", vpk_image([("txt", "carpeta", "árbol", {})]))
        self.assertEqual(result["entries"][0]["path"], "carpeta/árbol.txt")

    def test_vpk_empty_directory_tree(self):
        result = self.invoke("inspect-vpk", vpk_image())
        self.assertEqual(result["total_entries"], 0)
        self.assertEqual(result["entries"], [])

    def test_vpk_rejects_versions_and_tree_budget(self):
        for version in (0, 3, 0x30002):
            with self.subTest(version=version):
                self.invoke("inspect-vpk", struct.pack("<III", 0x55AA1234, version, 1) + b"\0",
                            valid=False)
        self.assertIn("budget", self.invoke("inspect-vpk",
                      struct.pack("<III", 0x55AA1234, 1, 32 * 1024 * 1024 + 1), valid=False))

    def test_vpk_rejects_unterminated_tree_and_truncated_preload(self):
        self.assertIn("unterminated", self.invoke("inspect-vpk",
                      struct.pack("<III", 0x55AA1234, 1, 3) + b"abc", valid=False))
        image = vpk_image([("txt", " ", "test", {"preload_size": 20})])
        self.assertIn("preload", self.invoke("inspect-vpk", image, valid=False))

    def test_vpk_rejects_wrong_entry_terminator(self):
        image = vpk_image([("txt", " ", "test", {"terminator": 0})])
        self.assertIn("entry terminator", self.invoke("inspect-vpk", image, valid=False))

    def test_vpk_rejects_traversal_absolute_and_windows_paths(self):
        for directory in ("../secret", "/absolute", "a/../b", "a//b", "C:/drive", "a\\b",
                          "a/.", "a/"):
            with self.subTest(directory=directory):
                self.assertIn("unsafe", self.invoke("inspect-vpk",
                              vpk_image([("txt", directory, "test", {})]), valid=False))
        for name in ("..", "../test", "a\\b"):
            with self.subTest(name=name):
                self.assertIn("unsafe", self.invoke("inspect-vpk",
                              vpk_image([("txt", " ", name, {})]), valid=False))

    def test_vpk_rejects_invalid_utf8(self):
        image = vpk_image([("txt", " ", "test", {})])
        image = image.replace(b"test\0", b"\xffest\0")
        self.assertIn("UTF-8", self.invoke("inspect-vpk", image, valid=False))

    def test_vpk_rejects_internal_and_external_overflow(self):
        image = vpk_image([("txt", " ", "test", {"archive": 0x7FFF, "offset": 3, "length": 2})],
                          data=b"abcd")
        self.assertIn("embedded", self.invoke("inspect-vpk", image, valid=False))
        image = vpk_image([("txt", " ", "test", {"offset": 0xFFFFFFF0, "length": 0x20})])
        self.assertIn("32-bit", self.invoke("inspect-vpk", image, valid=False))
        image = vpk_image([("txt", " ", "test", {"archive": 0xFFFF})])
        self.assertIn("archive index", self.invoke("inspect-vpk", image, valid=False))

    def test_vpk_empty_embedded_payload_preserves_unused_offset_sentinel(self):
        image = vpk_image([("vcs", "shaders", "empty", {"archive": 0x7FFF,
                           "offset": 0xFFFFFFFF, "length": 0})])
        result = self.invoke("inspect-vpk", image)
        self.assertEqual(result["file_data_section_size"], 0)
        self.assertEqual(result["entries"][0]["data_offset"], 0xFFFFFFFF)
        self.assertEqual(result["entries"][0]["data_length"], 0)
        self.assertEqual(result["entries"][0]["total_length"], 0)

    def test_vpk_nonempty_embedded_payload_cannot_use_offset_sentinel(self):
        image = vpk_image([("vcs", "shaders", "invalid", {"archive": 0x7FFF,
                           "offset": 0xFFFFFFFF, "length": 1})])
        self.assertIn("embedded", self.invoke("inspect-vpk", image, valid=False))

    def test_vpk_rejects_truncated_trailers(self):
        image = vpk_image(section_sizes=(0, 28, 48, 20))
        self.assertIn("trailer", self.invoke("inspect-vpk", image, valid=False))

    def test_vpk_signature_descriptor_extra_bytes_stay_uninspected(self):
        # Current signed Source 2 files may append key/signature bytes beyond
        # the declared 20-byte descriptor. They must not be mistaken for damage.
        image = vpk_image(trailer=b"x" * 20, section_sizes=(0, 0, 0, 20)) + b"key-signature"
        result = self.invoke("inspect-vpk", image)
        self.assertEqual(result["uninspected_trailing_bytes"], len(b"key-signature"))
        self.assertEqual(result["signature_section_size"], 20)

    def test_vpk_rejects_duplicate_paths_and_trailing_tree_junk(self):
        image = vpk_image([("txt", " ", "same", {}), ("txt", " ", "same", {})])
        self.assertIn("duplicate", self.invoke("inspect-vpk", image, valid=False))
        self.assertIn("tree terminator", self.invoke("inspect-vpk",
                      struct.pack("<III", 0x55AA1234, 1, 2) + b"\0x", valid=False))

    def test_vpk_listing_option_validation(self):
        for limit in ("-1", "1001", "abc", "1.2", ""):
            with self.subTest(limit=limit):
                self.assertIn("limit", self.invoke("inspect-vpk", vpk_image(),
                              "--limit", limit, valid=False))
        self.invoke("inspect-vpk", vpk_image(), "--filter", valid=False)


if __name__ == "__main__":
    unittest.main()
