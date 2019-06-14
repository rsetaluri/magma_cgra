import tempfile
import glob
import shutil
import os
from gemstone.common.testers import BasicTester
from canal.util import IOSide
import lassen.asm as asm
from archipelago import pnr
import pytest
import random
from cgra import create_cgra
from memory_core.memory_mode import Mode
from collections import deque


@pytest.fixture()
def io_sides():
    return IOSide.North | IOSide.East | IOSide.South | IOSide.West


@pytest.fixture(scope="module")
def dw_files():
    filenames = ["DW_fp_add.v", "DW_fp_mult.v"]
    dirname = "peak_core"
    result_filenames = []
    for name in filenames:
        filename = os.path.join(dirname, name)
        assert os.path.isfile(filename)
        result_filenames.append(filename)
    return result_filenames


@pytest.mark.parametrize("batch_size", [100])
def test_interconnect_point_wise(batch_size: int, dw_files, io_sides):
    # we test a simple point-wise multiplier function
    # to account for different CGRA size, we feed in data to the very top-left
    # SB and route through horizontally to reach very top-right SB
    # we configure the top-left PE as multiplier
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("p0", "data0")],
        "e1": [("I1", "io2f_16"), ("p0", "data1")],
        "e3": [("p0", "alu_res"), ("I2", "f2io_16")],
    }
    bus = {"e0": 16, "e1": 16, "e3": 16}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    x, y = placement["p0"]
    tile = interconnect.tile_circuits[(x, y)]
    add_bs = tile.core.get_config_bitstream(asm.umult0())
    for addr, data in add_bs:
        config_data.append((interconnect.get_config_addr(addr, 0, x, y), data))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()
    # set the PE core
    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    src_x0, src_y0 = placement["I0"]
    src_x1, src_y1 = placement["I1"]
    src_name0 = f"glb2io_16_X{src_x0:02X}_Y{src_y0:02X}"
    src_name1 = f"glb2io_16_X{src_x1:02X}_Y{src_y1:02X}"
    dst_x, dst_y = placement["I2"]
    dst_name = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    random.seed(0)
    for _ in range(batch_size):
        num_1 = random.randrange(0, 256)
        num_2 = random.randrange(0, 256)
        tester.poke(circuit.interface[src_name0], num_1)
        tester.poke(circuit.interface[src_name1], num_2)

        tester.eval()
        tester.expect(circuit.interface[dst_name], num_1 * num_2)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)
        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


@pytest.mark.parametrize("depth", [10, 100])
@pytest.mark.parametrize("stencil_width", [3, 5])
def test_interconnect_unified_buffer_stencil_valid(dw_files, io_sides,
                                                   stencil_width, depth):

    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "data_in"), ("p0", "data0")],
        "e1": [("m0", "data_out"), ("p0", "data1")],
        "e3": [("p0", "alu_res"), ("I1", "f2io_16")],
        "e4": [("i3", "io2f_1"), ("m0", "wen_in")],
        "e5": [("m0", "valid_out"), ("i4", "f2io_1")]
    }
    bus = {"e0": 16, "e1": 16, "e3": 16, "e4": 1, "e5": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    # in this case we configure m0 as double buffer mode
    mode = Mode.DB
    tile_en = 1

    mem_x, mem_y = placement["m0"]
    memtile = interconnect.tile_circuits[(mem_x, mem_y)]
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("depth"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, mem_x, mem_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stencil_width"),
                        0, mem_x, mem_y), stencil_width))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, mem_x, mem_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("flush_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("switch_db_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("rate_matched"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("iter_cnt"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("dimensionality"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_0"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_0"),
                        0, mem_x, mem_y), depth))

    # then p0 is configured as add
    pe_x, pe_y = placement["p0"]
    tile_id = pe_x << 8 | pe_y
    tile = interconnect.tile_circuits[(pe_x, pe_y)]

    add_bs = tile.core.get_config_bitstream(asm.add())
    for addr, data in add_bs:
        config_data.append(((addr << 24) | tile_id, data))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()
    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    src_x, src_y = placement["I0"]
    src = f"glb2io_16_X{src_x:02X}_Y{src_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    wen_x, wen_y = placement["i3"]
    wen = f"glb2io_1_X{wen_x:02X}_Y{wen_y:02X}"
    valid_x, valid_y = placement["i4"]
    valid = f"io2glb_1_X{valid_x:02X}_Y{valid_y:02X}"

    tester.poke(circuit.interface[wen], 1)

    counter = 0
    for i in range(3 * depth):
        tester.poke(circuit.interface[src], counter)
        tester.eval()

        if i < depth + stencil_width - 1:
            tester.expect(circuit.interface[valid], 0)
        elif i < 2 * depth:
            tester.expect(circuit.interface[valid], 1)
        elif i < 2 * depth + stencil_width - 1:
            tester.expect(circuit.interface[valid], 0)
        else:
            tester.expect(circuit.interface[valid], 1)

        # toggle the clock
        tester.step(2)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)
        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


@pytest.mark.parametrize("mode", [Mode.DB])
def test_interconnect_line_buffer_unified(dw_files, io_sides, mode):
    depth = 10
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "data_in"), ("p0", "data0")],
        "e1": [("m0", "data_out"), ("p0", "data1")],
        "e3": [("p0", "alu_res"), ("I1", "f2io_16")],
        "e4": [("i3", "io2f_1"), ("m0", "wen_in")],
        "e5": [("m0", "valid_out"), ("i4", "f2io_1")]
    }
    bus = {"e0": 16, "e1": 16, "e3": 16, "e4": 1, "e5": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    # in this case we configure m0 as line buffer mode
    tile_en = 1

    mem_x, mem_y = placement["m0"]
    memtile = interconnect.tile_circuits[(mem_x, mem_y)]
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("depth"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, mem_x, mem_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, mem_x, mem_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("rate_matched"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stencil_width"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("iter_cnt"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("dimensionality"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_0"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_0"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("flush_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("switch_db_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_x, mem_y), 1))

    # then p0 is configured as add
    pe_x, pe_y = placement["p0"]
    tile_id = pe_x << 8 | pe_y
    tile = interconnect.tile_circuits[(pe_x, pe_y)]

    add_bs = tile.core.get_config_bitstream(asm.add())
    for addr, data in add_bs:
        config_data.append(((addr << 24) | tile_id, data))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()

    tester.poke(circuit.interface["stall"], 1)

    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    src_x, src_y = placement["I0"]
    src = f"glb2io_16_X{src_x:02X}_Y{src_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    wen_x, wen_y = placement["i3"]
    wen = f"glb2io_1_X{wen_x:02X}_Y{wen_y:02X}"
    valid_x, valid_y = placement["i4"]
    valid = f"io2glb_1_X{valid_x:02X}_Y{valid_y:02X}"

    tester.poke(circuit.interface[wen], 1)

    # once the chip is stalled, it should only takes combinational inputs

    for i in range(10):
        tester.poke(circuit.interface[src], i + 1)
        tester.eval()
        tester.expect(circuit.interface[dst], i + 1)
        tester.step(2)

    tester.poke(circuit.interface["stall"], 0)
    tester.eval()

    counter = 0
    for i in range(200):
        tester.poke(circuit.interface[src], counter)
        tester.eval()

        if i == depth - 1:
            tester.expect(circuit.interface[valid], 0)
            tester.poke(circuit.interface[wen], 0)
        elif i == depth:
            tester.poke(circuit.interface[wen], 1)
            tester.expect(circuit.interface[valid], 0)
            counter += 1
        elif i >= depth + 1:
            tester.expect(circuit.interface[dst], i * 2 - depth - 2)
            tester.expect(circuit.interface[valid], 1)
            counter += 1
        else:
            tester.expect(circuit.interface[valid], 0)
            counter += 1

        # toggle the clock
        tester.step(2)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)

        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


def test_interconnect_sram(dw_files, io_sides):
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "addr_in")],
        "e1": [("m0", "data_out"), ("I1", "f2io_16")],
        "e2": [("i3", "io2f_1"), ("m0", "ren_in")]
    }
    bus = {"e0": 16, "e1": 16, "e2": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    x, y = placement["m0"]
    memtile = interconnect.tile_circuits[(x, y)]
    mode = Mode.SRAM
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, x, y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, x, y), 1))

    # in this case we configure (1, 0) as sram mode
    sram_data = []
    # add SRAM data
    for i in range(0, 1024, 4):
        feat_addr = i // 256 + 1
        mem_addr = i % 256
        sram_data.append((interconnect.get_config_addr(mem_addr, feat_addr, x,
                                                       y),
                          i + 10))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()
    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    for addr, data in sram_data:
        tester.configure(addr, data)
        # currently read back doesn't work
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, data)

    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    addr_x, addr_y = placement["I0"]
    src = f"glb2io_16_X{addr_x:02X}_Y{addr_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    ren_x, ren_y = placement["i3"]
    ren = f"glb2io_1_X{ren_x:02X}_Y{ren_y:02X}"

    tester.step(2)
    tester.poke(circuit.interface[ren], 1)
    tester.eval()

    for i in range(0, 1024, 4):
        tester.poke(circuit.interface[src], i)
        tester.eval()
        tester.step(2)
        tester.eval()
        tester.expect(circuit.interface[dst], i + 10)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)
        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


@pytest.mark.parametrize("depth", [1, 10, 1024])
def test_interconnect_fifo(dw_files, io_sides, depth):
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "data_in")],
        "e1": [("i3", "io2f_1"), ("m0", "wen_in")],
        "e2": [("i4", "io2f_1"), ("m0", "ren_in")],
        "e3": [("m0", "data_out"), ("I1", "f2io_16")],
        "e4": [("m0", "valid_out"), ("i4", "f2io_1")],
        "e5": [("m0", "empty"), ("i2", "f2io_1")],
        "e6": [("m0", "full"), ("i3", "f2io_1")]
    }
    bus = {"e0": 16, "e1": 1, "e2": 1, "e3": 16, "e4": 1, "e5": 1, "e6": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    # in this case we configure m0 as fifo mode
    mode = Mode.FIFO
    tile_en = 1

    almost_count = 3
    if(depth < 5):
        almost_count = 0

    mem_x, mem_y = placement["m0"]
    memtile = interconnect.tile_circuits[(mem_x, mem_y)]
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("depth"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, mem_x, mem_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, mem_x, mem_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("almost_count"),
                        0, mem_x, mem_y), almost_count))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("flush_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("switch_db_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_x, mem_y), 1))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()
    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    src_x, src_y = placement["I0"]
    src = f"glb2io_16_X{src_x:02X}_Y{src_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    wen_x, wen_y = placement["i3"]
    wen = f"glb2io_1_X{wen_x:02X}_Y{wen_y:02X}"
    valid_x, valid_y = placement["i4"]
    valid = f"io2glb_1_X{valid_x:02X}_Y{valid_y:02X}"
    ren_x, ren_y = placement["i4"]
    ren = f"glb2io_1_X{ren_x:02X}_Y{ren_y:02X}"
    full_x, full_y = placement["i3"]
    full = f"io2glb_1_X{full_x:02X}_Y{full_y:02X}"
    empty_x, empty_y = placement["i2"]
    empty = f"io2glb_1_X{empty_x:02X}_Y{empty_y:02X}"

    fifo = deque()
    valid_check = 0
    most_recent_read = 0
    for i in range(2048):

        tester.expect(circuit.interface[empty], len(fifo) == 0)
        tester.expect(circuit.interface[full], len(fifo) == depth)
        tester.expect(circuit.interface[valid], valid_check)

        # Pick random from (READ, WRITE, READ_AND_WRITE)
        move = random.randint(0, 3)
        if move == 0:
            # read
            tester.poke(circuit.interface[ren], 1)
            tester.step(2)
            if(len(fifo) > 0):
                most_recent_read = fifo.pop()
                tester.expect(circuit.interface[dst], most_recent_read)
                valid_check = 1
            else:
                valid_check = 0
            tester.poke(circuit.interface[ren], 0)
        elif move == 1:
            # write
            write_val = random.randint(0, 60000)
            tester.poke(circuit.interface[wen], 1)
            tester.poke(circuit.interface[src], write_val)
            if(len(fifo) < depth):
                fifo.appendleft(write_val)
            tester.step(2)
            tester.poke(circuit.interface[wen], 0)
            valid_check = 0
        elif move == 2:
            # r and w
            write_val = random.randint(0, 60000)
            tester.poke(circuit.interface[wen], 1)
            tester.poke(circuit.interface[ren], 1)
            tester.poke(circuit.interface[src], write_val)
            fifo.appendleft(write_val)
            tester.step(2)
            most_recent_read = fifo.pop()
            tester.expect(circuit.interface[dst], most_recent_read)
            tester.poke(circuit.interface[wen], 0)
            tester.poke(circuit.interface[ren], 0)
            valid_check = 1
        else:
            # If not doing anything, valid will be low, and we expect
            # to see the same output as before
            tester.step(2)
            valid_check = 0
            tester.expect(circuit.interface[dst], most_recent_read)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)
        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


def test_interconnect_double_buffer_unified(dw_files, io_sides):
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "data_in")],
        "e1": [("m0", "data_out"), ("I1", "f2io_16")],
        "e2": [("i3", "io2f_1"), ("m0", "wen_in")],
        "e3": [("i4", "io2f_1"), ("m0", "ren_in")],
        "e4": [("m0", "valid_out"), ("i4", "f2io_1")]
    }
    bus = {"e0": 16, "e1": 16, "e2": 1, "e3": 1, "e4": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    # in this case we configure m0 as line buffer mode
    tile_en = 1
    depth = 256
    range_0 = 2
    range_1 = 256
    stride_0 = 0
    stride_1 = 1
    dimensionality = 2
    starting_addr = 0
    mode = Mode.DB
    iter_cnt = range_0 * range_1

    mem_x, mem_y = placement["m0"]
    memtile = interconnect.tile_circuits[(mem_x, mem_y)]
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("depth"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, mem_x, mem_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, mem_x, mem_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("rate_matched"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stencil_width"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("iter_cnt"),
                        0, mem_x, mem_y), iter_cnt))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("dimensionality"),
                        0, mem_x, mem_y), dimensionality))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_0"),
                        0, mem_x, mem_y), stride_0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_0"),
                        0, mem_x, mem_y), range_0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_1"),
                        0, mem_x, mem_y), stride_1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_1"),
                        0, mem_x, mem_y), range_1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("flush_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("switch_db_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_x, mem_y), 1))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()

    tester.poke(circuit.interface["stall"], 1)

    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    src_x, src_y = placement["I0"]
    src = f"glb2io_16_X{src_x:02X}_Y{src_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    wen_x, wen_y = placement["i3"]
    wen = f"glb2io_1_X{wen_x:02X}_Y{wen_y:02X}"
    ren_x, ren_y = placement["i4"]
    ren = f"glb2io_1_X{ren_x:02X}_Y{ren_y:02X}"
    valid_x, valid_y = placement["i4"]
    valid = f"io2glb_1_X{valid_x:02X}_Y{valid_y:02X}"

    tester.poke(circuit.interface["stall"], 0)
    tester.eval()

    # 0,0,1,1,2,2,3,3,4,4...
    outputs = []
    for i in range(256):
        outputs.append(i)
        outputs.append(i)

    tester.poke(circuit.interface[ren], 1)
    counter = 0
    output_idx = 0
    for i in range(769):
        # We are just writing sequentially for this sample
        tester.poke(circuit.interface[wen], 1)
        tester.poke(circuit.interface[src], counter)
        counter += 1
        tester.eval()

        # Once the data starts coming out,
        # it should match the predefined list
        if(i == 256):
            tester.poke(circuit.interface[ren], 0)
            tester.eval()
            tester.expect(circuit.interface[valid], 0)
        elif(i > 256):
            tester.poke(circuit.interface[ren], 1)
            tester.eval()
            tester.expect(circuit.interface[valid], 1)
            tester.expect(circuit.interface[dst], outputs[output_idx])
            output_idx += 1

        # toggle the clock
        tester.step(2)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)

        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


def test_interconnect_db_alt_weights(dw_files, io_sides):
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "data_in")],
        "e1": [("m0", "data_out"), ("I1", "f2io_16")],
        "e2": [("i3", "io2f_1"), ("m0", "wen_in")],
        "e3": [("i4", "io2f_1"), ("m0", "ren_in")],
        "e4": [("m0", "valid_out"), ("i4", "f2io_1")]
    }
    bus = {"e0": 16, "e1": 16, "e2": 1, "e3": 1, "e4": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    # in this case we configure m0 as line buffer mode
    tile_en = 1
    depth = 2
    range_0 = 2
    range_1 = 256
    stride_0 = 1
    stride_1 = 0
    dimensionality = 2
    starting_addr = 0
    mode = Mode.DB
    iter_cnt = range_0 * range_1

    mem_x, mem_y = placement["m0"]
    memtile = interconnect.tile_circuits[(mem_x, mem_y)]
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("depth"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, mem_x, mem_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, mem_x, mem_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("rate_matched"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stencil_width"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("iter_cnt"),
                        0, mem_x, mem_y), iter_cnt))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("dimensionality"),
                        0, mem_x, mem_y), dimensionality))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_0"),
                        0, mem_x, mem_y), stride_0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_0"),
                        0, mem_x, mem_y), range_0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_1"),
                        0, mem_x, mem_y), stride_1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_1"),
                        0, mem_x, mem_y), range_1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("flush_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("switch_db_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_x, mem_y), 1))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()

    tester.poke(circuit.interface["stall"], 1)

    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    src_x, src_y = placement["I0"]
    src = f"glb2io_16_X{src_x:02X}_Y{src_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    wen_x, wen_y = placement["i3"]
    wen = f"glb2io_1_X{wen_x:02X}_Y{wen_y:02X}"
    ren_x, ren_y = placement["i4"]
    ren = f"glb2io_1_X{ren_x:02X}_Y{ren_y:02X}"
    valid_x, valid_y = placement["i4"]
    valid = f"io2glb_1_X{valid_x:02X}_Y{valid_y:02X}"

    tester.poke(circuit.interface["stall"], 0)
    tester.eval()

    # 0,0,1,1,2,2,3,3,4,4...
    outputs = []
    for i in range(256):
        outputs.append(0)
        outputs.append(1)

    tester.poke(circuit.interface[ren], 1)
    counter = 0
    output_idx = 0
    for i in range(514):
        # We are just writing sequentially for this sample
        tester.poke(circuit.interface[wen], 1)
        tester.poke(circuit.interface[src], counter)
        counter += 1
        tester.eval()

        # Once the data starts coming out,
        # it should match the predefined list
        if(i >= 2):
            tester.expect(circuit.interface[dst], outputs[output_idx])
            output_idx += 1

        # toggle the clock
        tester.step(2)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)

        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])


def test_interconnect_double_buffer_chain(dw_files, io_sides):
    chip_size = 2
    interconnect = create_cgra(chip_size, chip_size, io_sides,
                               num_tracks=3,
                               add_pd=True,
                               mem_ratio=(1, 2))

    netlist = {
        "e0": [("I0", "io2f_16"), ("m0", "data_in"), ("m1", "data_in")],
        "e1": [("m1", "data_out"), ("I1", "f2io_16")],
        "e2": [("i3", "io2f_1"), ("m0", "wen_in"), ("m1", "wen_in")],
        "e3": [("i4", "io2f_1"), ("m0", "ren_in"), ("m1", "ren_in")],
        "e4": [("m1", "valid_out"), ("i4", "f2io_1")],
        "e5": [("m0", "chain_out"), ("m1", "chain_in")],
        "e6": [("m0", "chain_valid_out"), ("m1", "chain_wen_in")]
    }
    bus = {"e0": 16, "e1": 16, "e2": 1, "e3": 1, "e4": 1, "e5": 16, "e6": 1}

    placement, routing = pnr(interconnect, (netlist, bus))
    config_data = interconnect.get_route_bitstream(routing)

    # in this case we configure m0 as line buffer mode
    tile_en = 1
    depth = 700
    range_0 = 2
    range_1 = 700
    stride_0 = 0
    stride_1 = 1
    dimensionality = 2
    starting_addr = 0
    mode = Mode.DB
    iter_cnt = range_0 * range_1

    mem_x, mem_y = placement["m0"]
    memtile = interconnect.tile_circuits[(mem_x, mem_y)]
    mcore = memtile.core
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("depth"),
                        0, mem_x, mem_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("mode"),
                        0, mem_x, mem_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("tile_en"),
                        0, mem_x, mem_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("rate_matched"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stencil_width"),
                        0, mem_x, mem_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("iter_cnt"),
                        0, mem_x, mem_y), iter_cnt))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("dimensionality"),
                        0, mem_x, mem_y), dimensionality))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_0"),
                        0, mem_x, mem_y), stride_0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_0"),
                        0, mem_x, mem_y), range_0))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("stride_1"),
                        0, mem_x, mem_y), stride_1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("range_1"),
                        0, mem_x, mem_y), range_1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("flush_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("switch_db_reg_sel"),
                        0, mem_x, mem_y), 1))
    # This tile's chain is grounded because it is the start of the chain
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("enable_chain"),
                        0, mem_x, mem_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore.get_reg_index("chain_idx"),
                        0, mem_x, mem_y), 0))

    mem_ext_x, mem_ext_y = placement["m1"]
    memtile_ch = interconnect.tile_circuits[(mem_ext_x, mem_ext_y)]
    mcore_ch = memtile_ch.core
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("depth"),
                        0, mem_ext_x, mem_ext_y), depth))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("mode"),
                        0, mem_ext_x, mem_ext_y), mode.value))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("tile_en"),
                        0, mem_ext_x, mem_ext_y), tile_en))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("rate_matched"),
                        0, mem_ext_x, mem_ext_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("stencil_width"),
                        0, mem_ext_x, mem_ext_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("iter_cnt"),
                        0, mem_ext_x, mem_ext_y), iter_cnt))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("dimensionality"),
                        0, mem_ext_x, mem_ext_y), dimensionality))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("stride_0"),
                        0, mem_ext_x, mem_ext_y), stride_0))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("range_0"),
                        0, mem_ext_x, mem_ext_y), range_0))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("stride_1"),
                        0, mem_ext_x, mem_ext_y), stride_1))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("range_1"),
                        0, mem_ext_x, mem_ext_y), range_1))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("flush_reg_sel"),
                        0, mem_ext_x, mem_ext_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("switch_db_reg_sel"),
                        0, mem_ext_x, mem_ext_y), 1))
    # This tile's chain in should come from the interconnect
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("chain_wen_in_reg_sel"),
                        0, mem_ext_x, mem_ext_y), 0))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("enable_chain"),
                        0, mem_ext_x, mem_ext_y), 1))
    config_data.append((interconnect.get_config_addr(
                        mcore_ch.get_reg_index("chain_idx"),
                        0, mem_ext_x, mem_ext_y), 1))

    circuit = interconnect.circuit()

    tester = BasicTester(circuit, circuit.clk, circuit.reset)
    tester.reset()

    tester.poke(circuit.interface["stall"], 1)

    for addr, index in config_data:
        tester.configure(addr, index)
        tester.config_read(addr)
        tester.eval()
        tester.expect(circuit.read_config_data, index)

    tester.done_config()

    src_x, src_y = placement["I0"]
    src = f"glb2io_16_X{src_x:02X}_Y{src_y:02X}"
    dst_x, dst_y = placement["I1"]
    dst = f"io2glb_16_X{dst_x:02X}_Y{dst_y:02X}"
    wen_x, wen_y = placement["i3"]
    wen = f"glb2io_1_X{wen_x:02X}_Y{wen_y:02X}"
    ren_x, ren_y = placement["i4"]
    ren = f"glb2io_1_X{ren_x:02X}_Y{ren_y:02X}"
    valid_x, valid_y = placement["i4"]
    valid = f"io2glb_1_X{valid_x:02X}_Y{valid_y:02X}"

    tester.poke(circuit.interface["stall"], 0)
    tester.eval()

    inputs = []
    for z in range(2):
        for i in range(depth):
            inputs.append(i)

    # 0,0,1,1,2,2,3,3,4,4...
    outputs = []
    for z in range(2):
        for i in range(depth):
            outputs.append(i)
            outputs.append(i)

    tester.poke(circuit.interface[ren], 1)
    input_idx = 0
    output_idx = 0
    for i in range(5 * depth):
        # We are just writing sequentially for this sample
        if(input_idx >= 2 * depth):
            tester.poke(circuit.interface[wen], 0)
        else:
            tester.poke(circuit.interface[wen], 1)
            tester.poke(circuit.interface[src], inputs[input_idx])
            input_idx += 1
        tester.eval()

        # Once the data starts coming out,
        # it should match the predefined list
        if(i >= depth):
            tester.expect(circuit.interface[dst], outputs[output_idx])
            output_idx += 1

        # toggle the clock
        tester.step(2)

    with tempfile.TemporaryDirectory() as tempdir:
        for genesis_verilog in glob.glob("genesis_verif/*.*"):
            shutil.copy(genesis_verilog, tempdir)
        for filename in dw_files:
            shutil.copy(filename, tempdir)
        shutil.copy(os.path.join("tests", "test_memory_core",
                                 "sram_stub.v"),
                    os.path.join(tempdir, "sram_512w_16b.v"))
        for aoi_mux in glob.glob("tests/*.sv"):
            shutil.copy(aoi_mux, tempdir)

        tester.compile_and_run(target="verilator",
                               magma_output="coreir-verilog",
                               magma_opts={"coreir_libs": {"float_DW"}},
                               directory=tempdir,
                               flags=["-Wno-fatal"])
