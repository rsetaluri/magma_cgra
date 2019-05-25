git checkout flow

pip install -e git://github.com/leonardt/fault.git#egg=fault
cd `pip show fault | grep Location | awk '{print $2}'`
git checkout rawloop
cd -
pip install -e git://github.com/phanrahan/magma.git#egg=magma
pip install -e git://github.com/thofstee/pyverilog.git#egg=pyverilog
cd `pip show pyverilog | grep Location | awk '{print $2}'`
git checkout patch-1
cd -

python garnet.py --width 8 --height 2 --verilog

cd tests/build
ln -s ../../genesis_verif/* .
ln -s ../../garnet.v .
wget https://raw.githubusercontent.com/StanfordAHA/garnet/master/global_buffer/genesis/TS1N16FFCLLSBLVTC2048X64M8SW.sv  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/lassen/master/tests/build/add.v  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/lassen/master/tests/build/mul.v  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/lassen/master/tests/build/CW_fp_add.v  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/lassen/master/tests/build/CW_fp_mult.v  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/garnet/master/tests/test_memory_core/sram_stub.v  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/garnet/master/tests/AO22D0BWP16P90.sv  # noqa
wget https://raw.githubusercontent.com/StanfordAHA/garnet/master/tests/AN2D0BWP16P90.sv  # noqa
ln -s sram_stub.v sram_512w_16b.v
cp ~/../thofstee/DW_tap.v . # TODO might be able to bypass that if we could switch to system_clk without having to do it over jtag...
cd -

python tests/test_garnet/_test_flow.py --from-verilog --recompile