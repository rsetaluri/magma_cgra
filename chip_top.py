import magma
from garnet import Garnet
from gemstone.generator.generator import Generator
from gemstone.generator.const import Const
from gemstone.common.jtag_type import JTAGType
import argparse

class Chip(Generator):
    def __init__(self, width, height):
        super().__init__()
        self.add_ports(
            jtag=JTAGType,
            clk_in=magma.In(magma.Clock),
            reset_in=magma.In(magma.AsyncReset),
        )
        self.garnet = Garnet(width, height)

        # Wire up top level ports to CGRA
        self.wire(self.ports.jtag, self.garnet.ports.jtag)
        self.wire(self.ports.clk_in, self.garnet.ports.clk_in)
        self.wire(self.ports.reset_in, self.garnet.ports.reset_in)
        

        for port in self.garnet.ports.values():
            port_name = port.qualified_name()
            port_width = 16 if "B16" in port_name else 1
            if "SB_IN" in port_name:
                # wire all Garnet inputs to 0 for now
                self.wire(port[0], Const(magma.bits(0, port_width)))

    def compile(self):
        raise NotImplementedError()

    def name(self):
        return "Chip"


def main():
    parser = argparse.ArgumentParser(description='Full SoC with Garnet CGRA')
    parser.add_argument('--width', type=int, default=32)
    parser.add_argument('--height', type=int, default=16)
    args = parser.parse_args()

    chip = Chip(width=args.width, height=args.height)
    chip_circ = chip.circuit()
    magma.compile("chip", chip_circ, output="coreir-verilog")


if __name__ == "__main__":
    main()
