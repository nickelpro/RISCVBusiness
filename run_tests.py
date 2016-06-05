#!/usr/bin/python

#
#   Copyright 2016 Purdue University
#   
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#   
#       http://www.apache.org/licenses/LICENSE-2.0
#   
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#
#   Filename:     run_tests.py
#
#   Created by:   Jacob R. Stevens
#   Email:        steven69@purdue.edu
#   Date Created: 06/01/2016
#   Description:  Script for running processor tests

import argparse
import sys
import glob
import subprocess
import os

FNULL = open(os.devnull, 'w')
END_COLOR = "\033[0m"
START_GREEN = "\033[92m"
START_RED = "\033[31m"

FILE_NAME = None
ARCH = "RV32I"
SUPPORTED_ARCHS = []
TEST_TYPE = "asm"
# Change this variable to the filename (minus extension)
# of the top level file for your project. This should
# match the file name given in the top level wscript
TOP_LEVEL = "RISCVBusiness" 

def parse_arguments():
      global ARCH, FILE_NAME, SUPPORTED_ARCHS, TEST_TYPE
      parser = argparse.ArgumentParser(description="Run various processor tests. This script expects to be run at the top level of the RISCV Business directory")
      parser.add_argument('--arch', '-a', dest='arch', type=str,
                          default="RV32I",
                          help="Specify the architecture targeted. Default: RV32I")
      parser.add_argument('--test', '-t', dest='test_type', type=str, default="asm",
                          help="Specify what type of tests to run. Default: asm")
      parser.add_argument('file_name', metavar='file_name', type=str,
                          nargs='?',
                          help="Run all tests that begin with this string. Optional")
      args = parser.parse_args()
      ARCH = args.arch
      FILE_NAME = args.file_name
      TEST_TYPE = args.test_type
      
      if TEST_TYPE not in ['asm', 'c', 'self']:
          print "ERROR: " + TEST_TYPE + " is not a supported test type"
          sys.exit(1)
      
      test_file_dir = TEST_TYPE + '-tests/'
      SUPPORTED_ARCHS = glob.glob('./verification/' + test_file_dir + '*')
      SUPPORTED_ARCHS = [a.split('/'+test_file_dir)[1] for a in SUPPORTED_ARCHS]
      if ARCH not in SUPPORTED_ARCHS:
          print "ERROR: No " + TEST_TYPE + " tests exist for " + ARCH
          sys.exit(1)

# compile_asm takes a file_name as input and assembles the file pointed
# to by that file name. It also takes the elf file that is the result
# of that compilation and creates a meminit.hex file for it
def compile_asm(file_name):
    # compile all of the files
    short_name = file_name.split(ARCH+'/')[1]
    output_name = './verification/asm-tests/' + ARCH + '/'
    output_name = output_name + short_name.split(".")[0] + ".elf"
    cmd_arr = ['riscv64-unknown-elf-gcc', '-m32', '-static',
                '-mcmodel=medany', '-fvisibility=hidden', '-nostdlib',
                '-nostartfiles', '-T./verification/asm-env/link.ld',
                '-I./verification/asm-env', file_name, '-o', output_name]
    failure = subprocess.call(cmd_arr)
    if failure:
        return -1
    
    # create an meminit.hex file from the elf file produced above
    cmd_arr = ['elf2hex', '8', '65536', output_name]
    hex_file_loc = './meminit.hex'
    with open(hex_file_loc, 'w') as hex_file:
        failure = subprocess.call(cmd_arr, stdout=hex_file)
    if failure:
        return -2
    else:
        return 0

def invert_bin_string(bin_string):
    inverted = ''
    while len(bin_string) < 8:
        bin_string = '0' + bin_string
    for bit in bin_string:
        if bit == '0':
            inverted = inverted + '1'
        else:
            inverted = inverted + '0'
    return inverted


# Returns the string representation of the
# checksum for the given data and address values
def calculate_checksum_str(data, addr):
    addr = addr/4
    high_addr = (addr & 0xFF00) >> 8
    low_addr = addr & 0x00FF
    data1 = data & 0x000000FF
    data2 = (data & 0x0000FF00) >> 8
    data3 = (data & 0x00FF0000) >> 16
    data4 = (data & 0xFF000000) >> 24
    checksum = 4 + high_addr + low_addr
    checksum += data1 + data2 + data3 + data4
    checksum = checksum & 0xFF
    checksum = int(invert_bin_string(bin(checksum)[2:]),2)
    checksum += 1
    return hex(checksum)[2:] 

# Create a temp file that consists of the Intel HEX format
# version of the meminit.hex file, delete the original log file
# and rename the temp file to the original's name
def clean_init_hex(file_name):
    init_output = "./meminit.hex" 
    cleaned_location = init_output[:len(file_name)-4] + "_clean.hex"
    addr = 0x00
    with open(init_output, 'r') as init_file:
        cleaned_file = open(cleaned_location, 'w')

        for line in init_file:
            stripped_line = line[:len(line)-1]
            for i in range(len(stripped_line), 0, -8):
                data_word = stripped_line[i-8:i]
                checksum = calculate_checksum_str(int(data_word, 16), addr)
                if len(checksum) < 2:
                    checksum = '0' + checksum
                addr_str = hex(addr/4)[2:]
                #left pad the string with 0s until 4 hex digits
                while len(addr_str) < 4:
                    addr_str = '0' + addr_str
                if data_word != "00000000":
                    out = ":04" + addr_str + "00" + data_word + checksum + '\n'
                    # ignore the ELF header
                    if addr >= 0x200:
                        cleaned_file.write(out)
                addr += 0x4
        # add the EOL record to the file
        cleaned_file.write(":00000001FF")
        cleaned_file.close()
    subprocess.call(['rm', init_output])
    subprocess.call(['mv', cleaned_location, init_output])
    return

# Create a temp file that consists of the Intel HEX format
# version of the spike log file, delete the original log file
# and rename the temp file to the original's name
def clean_spike_output(file_name):
    spike_output = file_name[:len(file_name)-2] + '_spike.hex'
    cleaned_location = file_name[:len(file_name)-2] + '_spike_clean.hex'
    addr = 0x200
    with open(spike_output, 'r') as spike_file:
        cleaned_file = open(cleaned_location, 'w')
        for line in spike_file:
            stripped_line = line[:len(line)-1]
            for i in range(len(stripped_line), 0, -8):
                data_word = stripped_line[i-8:i]
                checksum = calculate_checksum_str(int(data_word, 16), addr)
                if len(checksum) < 2:
                    checksum = '0' + checksum
                addr_str = hex(addr/4)[2:]
                #left pad the string with 0s until 4 hex digits
                while len(addr_str) < 4:
                    addr_str = '0' + addr_str
                if data_word != "00000000":
                    out = ":04" + addr_str + "00" + data_word + checksum + '\n'
                    cleaned_file.write(out)
                addr += 0x4
        # add the EOL record to the file
        cleaned_file.write(":00000001FF")
        cleaned_file.close()
    subprocess.call(['rm', spike_output])
    subprocess.call(['mv', cleaned_location, spike_output])
    return

def run_sim(file_name):
    cmd_arr = ['waf', 'configure', '--top_level=' + TOP_LEVEL]
    failure = subprocess.call(cmd_arr, stdout=FNULL)
    if failure:
      return -1
    return 0;
    cmd_arr = ['waf', 'verify_source']
    failure = subprocess.call(cmd_arr, stdout=FNULL)
    if failure:
        return -2
    return 0

def run_spike_asm(file_name):
    # the object file should already exist from calling compile_asm
    elf_name = file_name[:len(file_name)-2] + '.elf'
    log_name = file_name[:len(file_name)-2] + '_spike.hex'
    cmd_arr = ['spike', '--isa=RV32IM', '+signature=' + log_name, elf_name]
    failure = subprocess.call(cmd_arr)
    if failure:
        return -1
    return 0

def compare_results(f):
    short_name = f.split(ARCH+'/')[1]
    sim_name = "./cpu.hex" 
    spike_name = f[:len(f)-2] + '_spike.hex'
    pass_msg = '{0:<40}{1:>20}'.format(short_name,START_GREEN + '[PASSED]' + END_COLOR)
    fail_msg = '{0:<40}{1:>20}'.format(short_name,START_RED + '[FAILED]' + END_COLOR)
    failure = subprocess.call(['diff', sim_name, spike_name],
                stdout=FNULL, stderr=subprocess.STDOUT)
    if failure:
        print fail_msg
        return -1
    else:
        print pass_msg
        return 0

if __name__ == '__main__':
    parse_arguments()  
    
    # asm comparison testing
    if TEST_TYPE == "asm":
        if FILE_NAME is None:
            files = glob.glob("./verification/"+TEST_TYPE+"-tests/"+ARCH+"/*.S")
        else:
            files = glob.glob("./verification/"+TEST_TYPE+"-tests/"+ARCH+"/"+FILE_NAME+"*.S")
        for f in files:
            ret = compile_asm(f)
            clean_init_hex(f)
            if ret != 0:
                if ret == -1:
                    print "An error has occured during GCC compilation"
                elif ret == -2:
                    print "An erro has occured converting elf to hex"
                sys.exit(1)
            ret = run_sim(f)
            if ret != 0:
                if ret == -1:
                  print "An error has occurred while setting waf's top level"
                elif ret == -2:
                    print "An error has occurred while running sim"
                sys.exit(1)
            ret = run_spike_asm(f)
            if ret != 0:
                print "An error has occurred during running Spike"
                sys.exit(1)
            clean_spike_output(f)
            compare_results(f)
    # C comparison testing
    elif TEST_TYPE == "c":
        if FILE_NAME is None:
            files = glob.glob("./verification/"+TEST_TYPE+"-tests/"+ARCH+"/*.c")
        else:
            files = glob.glob("./verification/"+TEST_TYPE+"-tests/"+ARCH+"/"+FILE_NAME+"*.c")
        print "To be implemented"
    # self tests
    elif TEST_TYPE == "self":
        for f in files:
            if ".S" in f:
                print "To be implemented."
            elif ".c" in f:
                print "To be implemented"
