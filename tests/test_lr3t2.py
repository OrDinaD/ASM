import pathlib
import struct
import subprocess

import pytest

from unicorn import Uc, UC_ARCH_X86, UC_MODE_16
from unicorn.x86_const import UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_IP, UC_X86_REG_SP, UC_X86_REG_SS

ROOT = pathlib.Path(__file__).resolve().parents[1]
ASM_PATH = ROOT / "LR3T2.asm"
BIN_PATH = ROOT / "LR3T2.com"

BASE_ADDR = 0x100
PARSE_ADDR = 0x16C
PARSE_RET = 0x13B
SORT_ADDR = 0x1AC
SORT_RET = 0x14F
BUILD_ADDR = 0x268
BUILD_RET = 0x159

INPUT_BUFFER = 0x03C4
BUFFER_DATA = 0x03C6
INPUT_LENGTH = 0x048E
WORD_COUNT = 0x0490
SORTED_LENGTH = 0x0492
WORD_OFFSETS = 0x0494
WORD_LENGTHS = 0x055C

MAX_LEN = 200
MAX_WORDS = 100
STACK_ADDR = 0xFF00
WORK_AREA_SIZE = (0x0632 - WORD_COUNT)


def assemble_binary():
    subprocess.run(
        ["nasm", "-f", "bin", "-o", str(BIN_PATH), str(ASM_PATH)],
        check=True,
        cwd=ROOT,
    )


@pytest.fixture(scope="module")
def binary():
    assemble_binary()
    return BIN_PATH.read_bytes()


def make_emulator(binary_blob: bytes) -> Uc:
    mu = Uc(UC_ARCH_X86, UC_MODE_16)
    mu.mem_map(0x0000, 0x10000)
    mu.mem_write(BASE_ADDR, binary_blob)
    mu.reg_write(UC_X86_REG_CS, 0)
    mu.reg_write(UC_X86_REG_DS, 0)
    mu.reg_write(UC_X86_REG_ES, 0)
    mu.reg_write(UC_X86_REG_SS, 0)
    return mu


def run_subroutine(mu: Uc, start: int, ret: int):
    mu.reg_write(UC_X86_REG_IP, start)
    mu.reg_write(UC_X86_REG_SP, STACK_ADDR)
    mu.mem_write(STACK_ADDR, struct.pack("<H", ret))
    mu.emu_start(start, ret)


def write_word(mu: Uc, address: int, value: int):
    mu.mem_write(address, struct.pack("<H", value))


def read_word(mu: Uc, address: int) -> int:
    return struct.unpack("<H", mu.mem_read(address, 2))[0]


def prepare_input(mu: Uc, text: str):
    data = text.encode("ascii")
    buffer = bytearray(MAX_LEN + 2)
    buffer[0] = MAX_LEN
    buffer[1] = len(data)
    buffer[2:2 + len(data)] = data
    mu.mem_write(INPUT_BUFFER, bytes(buffer))
    write_word(mu, INPUT_LENGTH, len(data))
    mu.mem_write(WORD_COUNT, b"\x00" * WORK_AREA_SIZE)
    mu.mem_write(WORD_OFFSETS, b"\x00" * (MAX_WORDS * 2))
    mu.mem_write(WORD_LENGTHS, b"\x00" * (MAX_WORDS * 2))


def execute_pipeline(mu: Uc, text: str, include_build: bool = True):
    prepare_input(mu, text)
    run_subroutine(mu, PARSE_ADDR, PARSE_RET)
    run_subroutine(mu, SORT_ADDR, SORT_RET)
    if include_build:
        run_subroutine(mu, BUILD_ADDR, BUILD_RET)


def read_output(mu: Uc) -> bytes:
    length = read_word(mu, SORTED_LENGTH)
    return mu.mem_read(BUFFER_DATA, length)


def test_parse_empty_input(binary):
    mu = make_emulator(binary)
    prepare_input(mu, "")
    run_subroutine(mu, PARSE_ADDR, PARSE_RET)
    assert read_word(mu, WORD_COUNT) == 0


def test_single_word_output(binary):
    mu = make_emulator(binary)
    execute_pipeline(mu, "hello")
    assert read_word(mu, WORD_COUNT) == 1
    assert read_word(mu, SORTED_LENGTH) == 7
    assert read_output(mu) == b"hello\r\n"


def test_multiple_words_with_duplicates(binary):
    mu = make_emulator(binary)
    execute_pipeline(mu, "zeta alpha beta alpha")
    assert read_word(mu, WORD_COUNT) == 4
    assert read_output(mu) == b"alpha alpha beta zeta\r\n"


def test_only_delimiters(binary):
    mu = make_emulator(binary)
    execute_pipeline(mu, " \t \r", include_build=True)
    assert read_word(mu, WORD_COUNT) == 0
    assert read_word(mu, SORTED_LENGTH) == 2
    assert read_output(mu) == b"\r\n"


def test_max_length_single_word(binary):
    mu = make_emulator(binary)
    long_word = "a" * MAX_LEN
    execute_pipeline(mu, long_word)
    assert read_word(mu, WORD_COUNT) == 1
    assert read_word(mu, SORTED_LENGTH) == MAX_LEN + 2
    assert read_output(mu) == long_word.encode("ascii") + b"\r\n"
