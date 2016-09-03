#! /usr/bin/env python
# encoding: utf-8

import os
toolpath = os.environ['WAFDIR'] + '/../waf-extensions'

top = '.'
out = 'build'

def options(ctx):
    ctx.load('SoC_build_mgr', tooldir=toolpath)
    ctx.load('Incisive', tooldir=toolpath)
    ctx.load('Syn_support', tooldir=toolpath)
    ctx.load('why')

def configure(ctx):
    ctx.load('SoC_build_mgr', tooldir=toolpath)
    ctx.load('Incisive', tooldir=toolpath)
    ctx.load('Syn_support', tooldir=toolpath)

    ctx.setup_hdl_module('RISCVBusiness',
      includes = ['include'],
      src_dir = ['packages','src'],
      tb = 'tb_RISCVBusiness',
      tb_includes = ['include']
    )
    ctx.setup_hdl_module('RISCVBusiness_self_test',
      includes = ['include'],
      src_dir = ['packages','src'],
      tb = 'tb_RISCVBusiness_self_test',
      tb_includes = ['include']
    )
    ctx.setup_hdl_module('alu', 
      includes = ['include'],
      src_dir = ['packages','src'],
      tb = 'tb_alu',
      tb_includes = ['include']
    )

def build(ctx):
    pass
