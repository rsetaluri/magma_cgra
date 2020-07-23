#!/bin/bash

function help {
    cat <<EOF

Usage: $0 [OPTION] <module>,<subgraph>,<subsubgraph>... --steps <step1>,<step2>...

Options:
  --branch <b>  only run test if in git branch <b>
  -v, --verbose VERBOSE mode
  -q, --quiet   QUIET mode
  -h, --help    help and examples
  --debug       DEBUG mode
  --steps       step(s) to run in the indicated (sub)graph. default = 'lvs,drc'

Examples:
    $0 Tile_PE
    $0 Tile_MemCore
    $0 Tile_PE --branch 'devtile*'
    $0 --verbose Tile_PE --steps synthesis
    $0 full_chip tile_array Tile_PE --steps synthesis
    
EOF
}

# Args
VERBOSE=false

exit_unless_verbose="exit 13"
# Don't want this no more
# [ "VERBOSE" == "true" ] && \
#     exit_unless_verbose="echo ERROR but continue anyway"

# Tile_PE
# module=Tile_PE
# module=$1

modlist=()
build_sequence='lvs,gls'
while [ $# -gt 0 ] ; do
    case "$1" in
        -h|--help)    help; exit;    ;;
        -v|--verbose) VERBOSE=true;  ;;
        -q|--quiet)   VERBOSE=false; ;;
        --debug)      DEBUG=true;    ;;
        --branch)     shift; branch_filter="$1";  ;;
        --steps)      shift; build_sequence="$1"; ;;
        -*)
            echo "***ERROR unrecognized arg '$1'"; help; exit; ;;
        *)
            modlist+=($1); ;;
    esac
    shift
done
        
# Turn build sequence into an array e.g. 'lvs,gls' => 'lvs gls'
build_sequence=`echo $build_sequence | tr ',' ' '`

# step_synthesis=synopsys-dc-synthesis
# 
# # build_sequence=(a b synthesis)
# for step in ${build_sequence[@]}; do
#     if [ "$step_$step" ] ; then echo $step = $step_$step; fi
# done

# E.g. 'step_alias syn' returns 'synopsys-dc-synthesis'
function step_alias {
    case "$1" in
        init)      echo cadence-innovus-init    ;;
        gds)       echo mentor-calibre-gdsmerge ;;
        tape)      echo mentor-calibre-gdsmerge ;;
        lvs)       echo mentor-calibre-lvs      ;;
        syn)       echo synopsys-dc-synthesis   ;;
        synthesis) echo synopsys-dc-synthesis   ;;

        *)             echo "$1" ;;
    esac
}

# for step in ${build_sequence[@]}; do
#     echo -n "    $step -> "
#     step=`step_alias $step`
#     echo $step
# done
# exit



# firstmod=${modlist[0]}; modlist=(${modlist[@]:1})

DEBUG=true
if [ "$DEBUG"=="true" ]; then
    echo VERBOSE=$VERBOSE
    echo module=${modlist[0]}
    echo firstmod=${modlist[0]}
    echo subgraphs=\(${modlist[@]:1}\)
    # for m in ${modlist[@]}; do echo "  m=$m"; done
fi

if [ "$branch_filter" ]; then
    echo '+++ BRANCH FILTER'
    echo ""
    echo "Note tests only work in branches that match regexp '$branch_filter'"
    if [ "$BUILDKITE_BRANCH" ]; then
        branch=${BUILDKITE_BRANCH}
        echo "It looks like we are running from within buildkite"
        echo "And it looks like we are in branch '$branch'"

    else 
        branch=`git symbolic-ref --short HEAD`
        echo "It looks like we are *not* running from within buildkite"
        echo "We appear to be in branch '$branch'"
    fi
    echo ""

    # Note DOES NOT WORK if $branch_filter is in quotes e.g. "$branch_filter" :o
    if [[ "$branch" =~ $branch_filter ]]; then
        echo "Okay that's the right branch, off we go."
    else
        if [ "$BUILDKITE_LABEL" ]; then
            # https://buildkite.com/docs/agent/v3/cli-annotate
            cmd="buildkite-agent annotate --append"
            label="$BUILDKITE_LABEL"
        else
            cmd='cat'
            # label="$module"
            label=${modlist[0]}
        fi

        ems='!!!'
        echo "NOTE '$label' TEST DID NOT ACTUALLY RUN$ems"$'\n' | $cmd
        # echo "- Tests only work in branch '$allowed_branch'" | $cmd
        echo "- This test is disabled except for branches that match regex '$branch_filter'" | $cmd
        echo "- and we appear to be in branch '$branch'"$'\n' | $cmd
        exit 0
    fi
fi

# Exit on error in any stage of any pipeline (is this a good idea?)
set -eo pipefail

# Running out of space in /tmp!!?
export TMPDIR=/sim/tmp

# Colons is stupids, define "PASS" to use instead
PASS=:

########################################################################
# Find GARNET_HOME
function where_this_script_lives {
  # Where this script lives
  scriptpath=$0      # E.g. "build_tarfile.sh" or "foo/bar/build_tarfile.sh"
  scriptdir=${0%/*}  # E.g. "build_tarfile.sh" or "foo/bar"
  if test "$scriptdir" == "$scriptpath"; then scriptdir="."; fi
  # scriptdir=`cd $scriptdir; pwd`
  (cd $scriptdir; pwd)
}
script_home=`where_this_script_lives`

# setup assumes this script lives in garnet/mflowgen/test/
garnet=`cd $script_home/../..; pwd`

# Oop "make rtl" (among others maybe) needs GARNET_HOME env var
export GARNET_HOME=$garnet

########################################################################
# Build environment and check requirements
function check_pyversions {
    echo ""
    echo PYTHON PATHS:
    echo "--------------"
    type -P python
    python --version
    pip --version
    echo "--------------"
}

if [ "$USER" == "buildkite-agent" ]; then
    echo "--- ENVIRONMENT"; echo ""

    venv=/usr/local/venv_garnet
    if test -d $venv; then
        echo "USE PRE-BUILT PYTHON VIRTUAL ENVIRONMENT"
        source $venv/bin/activate
    else
        echo "CANNOT FIND PRE-BUILT PYTHON VIRTUAL ENVIRONMENT"
        echo "- building a new one from scratch"
        # JOBDIR should be per-buildstep environment e.g.
        # /sim/buildkite-agent/builds/bigjobs-1/tapeout-aha/
        JOBDIR=$BUILDKITE_BUILD_CHECKOUT_PATH
        pushd $JOBDIR
          /usr/local/bin/python3 -m venv venv ;# Builds "$JOBDIR/venv" maybe
          source $JOBDIR/venv/bin/activate
        popd
    fi

    check_pyversions
    # pip install -r $garnet/requirements.txt
    # Biting the bullet; also, it's the right thing to do I guess
    pip install -U -r $garnet/requirements.txt
fi

# Lots of useful things in /usr/local/bin. coreir for instance ("type"=="which")
# echo ""; type coreir
export PATH="$PATH:/usr/local/bin"; hash -r
# type coreir; echo ""

# Set up paths for innovus, genus, dc etc.
# source $garnet/.buildkite/setup.sh
# source $garnet/.buildkite/setup-calibre.sh
# Use the new stuff
source $garnet/mflowgen/setup-garnet.sh

# Recheck python/pip versions b/c CAD modules can muck them up :(
check_pyversions

# OA_HOME weirdness
# OA_HOME *** WILL DRIVE ME MAD!!! ***
echo "--- UNSET OA_HOME"
echo ""
echo "buildkite (but not arm7 (???)) errs if OA_HOME is set"
echo "BEFORE: OA_HOME=$OA_HOME"
echo "unset OA_HOME"
unset OA_HOME
echo "AFTER:  OA_HOME=$OA_HOME"
echo ""

# Okay let's check and see what we got.
echo "--- REQUIREMENTS CHECK"; echo ""
$garnet/bin/requirements_check.sh -v --debug

# Make a build space for mflowgen; clone mflowgen
echo "--- CLONE MFLOWGEN REPO"
[ "$VERBOSE" == "true" ] && (echo ""; echo "--- pwd="`pwd`; echo "")
if [ "$USER" == "buildkite-agent" ]; then
    build=$garnet/mflowgen/test
else
    build=/sim/$USER
fi
test  -d $build || mkdir $build; cd $build
test  -d $build/mflowgen || git clone https://github.com/cornell-brg/mflowgen.git
mflowgen=$build/mflowgen
echo ""

########################################################################
# ADK SETUP / CHECK

echo "--- ADK SETUP / CHECK"
if [ "$USER" == "buildkite-agent" ]; then
    pushd $mflowgen/adks

    # Check out official adk repo?
    #   test -d tsmc16-adk || git clone http://gitlab.r7arm-aha.localdomain/alexcarsello/tsmc16-adk.git
    # Yeah, no, that ain't gonna fly. gitlab repo requires username/pwd permissions and junk
    # Instead, let's just use a cached copy
    # cached_adk=/sim/steveri/mflowgen/adks/tsmc16-adk
    cached_adk=/sim/steveri/mflowgen/adks/tsmc16
    echo copying adk from ${cached_adk}
    ls -l ${cached_adk}

    # Symlink to steveri no good. Apparently need permission to "touch" adk files(??)
    # test -e tsmc16 || ln -s ${cached_adk} tsmc16
    if test -e tsmc16; then
        echo WARNING destroying and replacing existing adk/tsmc16
        set -x; /bin/rm -rf tsmc16; set +x
    fi
    echo COPYING IN A FRESH ADK
    set -x; cp -rpH ${cached_adk} .; set +x
    popd
fi
export MFLOWGEN_PATH=$mflowgen/adks
echo "Set MFLOWGEN_PATH=$MFLOWGEN_PATH"; echo ""

########################################################################
# HIERARCHICAL BUILD AND RUN

echo "--- HIERARCHICAL BUILD AND RUN"
function build_module {
    set -x
    modname=$1 ; # E.g. "Tile_PE"

    # Really only need to do this once
    # export MFLOWGEN_PATH=/sim/steveri/mflowgen/adks ; # What? No!!!

    # Looking for a "make list" line that matches modname e.g.
    # " -   1 : Tile_PE"
    # In which case we build a prefix "1-" so as to build subdir "1-Tile_PE"
    if ! test -f Makefile; then 
        modpfx=''
        dirname=$modpfx$modname; # E.g. "1-Tile_PE"
        echo "--- ...BUILD MODULE '$dirname'"
    else
        # Find appropriate directory name for subgraph e.g. "14-tile_array"
        set -x; make list | awk '$NF == "'$modname'" {print}'; set +x
        modpfx=`make list | awk '$NF == "'$modname'" {print $2 "-"}'`
        dirname=$modpfx$modname; # E.g. "1-Tile_PE"
        echo "--- ...BUILD SUBGRAPH '$dirname'"
    fi
    set -x
    mkdir $dirname; cd $dirname
    mflowgen run --design $garnet/mflowgen/$modname
    # mflowgen stash link --path /home/ajcars/tapeout_stash/2020-0509-mflowgen-stash-ec95d0
    set +x
}
if [ "$DEBUG" ]; then
    echo firstmod=${modlist[0]}
    echo subgraphs=\(${modlist[@]:1}\)
fi

########################################################################
# build_module full_chip
# build_module tile_array
# build_module Tile_PE
########################################################################
# build_module $firstmod
for m in ${modlist[@]}; do 
    build_module $m; 
done

touch .stamp; # Breaks if don't do this before final step; I forget why...? Chris knows...
set +x
for step in ${build_sequence[@]}; do

    # Expand aliases e.g. "syn" -> "synopsys-dc-synthesis"
    echo -n "    $step -> "
    step=`step_alias $step`
    echo $step

    if [ "$step" == "none" ]; then 
        echo '--- DONE (for now)'
        echo pre-exit pwd=`pwd`
        exit
    fi

    if [ "$step" == "copy" ]; then 
        echo "--- ......SETUP context from gold cache (`date +'%a %H:%M'`)"
        gold=/sim/buildkite-agent/gold

        echo cp -rpf $gold/full_chip/*tile_array/0-Tile_MemCore .
        cp -rpf $gold/full_chip/*tile_array/0-Tile_MemCore .
        
        echo cp -rpf $gold/full_chip/*tile_array/1-Tile_PE .
        cp -rpf $gold/full_chip/*tile_array/1-Tile_PE .
        
        # If stop copying here, still takes an hour
        # What if we copy more stuff?

#             2-constraints \
#             3-custom-cts-overrides \
#             4-custom-init \
#             5-custom-lvs-rules \
#             9-rtl \
#             11-tsmc16 \
#             12-synopsys-dc-synthesis \
# 

        for f in \
            2-constraints \
            9-rtl \
            11-tsmc16 \
            12-synopsys-dc-synthesis \
        ; do
            echo cp -rpf $gold/full_chip/*tile_array/$f .
            cp -rpf $gold/full_chip/*tile_array/1-Tile_PE .
        done
        echo "+++ ......TODO list (`date +'%a %H:%M'`)"
        make -n cadence-innovus-init | grep 'mkdir.*output' | sed 's/.output.*//'
        continue
    fi

    


    echo "--- ......MAKE $step (`date +'%a %H:%M'`)"
#     if [ "$step" == "synthesis" ]; then step=synopsys-dc-synthesis; fi
    echo "make $step"
    make $step |& tee make.log || set FAIL
    if [ "$FAIL" ]; then
        echo '+++ FAIL'
        echo 'Looks like we failed, here are some errors maybe:'
        echo grep -i error mflowgen-run.log
        grep -i error mflowgen-run.log
        exit 13
    fi
done
set -x

exit

# ##############################################################################
# ##############################################################################
# ##############################################################################
# # OLD STUFF, much of which we will want to reuse eventually...
# # So DON'T DELETE (yet)
# 
# module=${modlist[0]}
# 
# # test_module.sh full_chip tile_array Tile_PE
# # scp kiwi:/nobackup/steveri/github/garnet/mflowgen/test/test_module.sh .
# 
# ##############################################################################
# # Don't write over existing module
# if test -d $mflowgen/$module; then
#     echo "oops $mflowgen/$module exists already, not gonna write over that"
#     echo "giving up now love ya bye-bye"
#     exit 13
# fi
# 
# # e.g. module=Tile_PE or Tile_MemCore
# echo ""; set -x
# mkdir $mflowgen/$module; cd $mflowgen/$module
# ../configure --design $garnet/mflowgen/$module
# set +x; echo ""
# 
# # Targets: run "make list" and "make status"
# # make list
# #
# # echo "make mentor-calibre-drc \
# #   |& tee mcdrc.log \
# #   | gawk -f $script_home/filter.awk"
# 
# # ########################################################################
# # # Makefile assumes "python" means "python3" :(
# # # Note requirements_check.sh (above) not sufficient to fix this :(
# # # Python check
# # echo "--- PYTHON=PYTHON3 FIX"
# # v=`python -c 'import sys; print(sys.version_info[0]*1000+sys.version_info[1])'`
# # echo "Found python version $v -- should be at least 3007"
# # if [ $v -lt 3007 ] ; then
# #   echo ""
# #   echo "WARNING found python version $v -- should be 3007"
# #   echo "WARNING I will try and fix it for you with my horrible hackiness"
# #   # On arm7 machine it's in /usr/local/bin, that's just how it is
# #   echo "ln -s bin/python /usr/local/bin/python3"
# #   test -d bin || mkdir bin
# #   (cd bin; ln -s /usr/local/bin/python3 python)
# #   export PATH=`pwd`/bin:"$PATH"
# #   hash -r
# #   v=`python -c 'import sys; print(sys.version_info[0]*1000+sys.version_info[1])'`
# #   echo "Found python version $v -- should be at least 3007"
# #   if [ $v -lt 3007 ] ; then
# #     echo ""; echo 'ERROR could not fix python sorry!!!'
# #   fi
# #   echo
# # fi
# # echo ""
# 
# 
# set -x
# which python; which python3
# set +x
# 
# 
# 
# if [ "$USER" != "buildkite-agent" ]; then
#     # # Prime the pump w/req-chk results
#     cat $tmpfile.reqchk > mcdrc.log; /bin/rm $tmpfile.reqchk
#     echo "----------------------------------------" >> mcdrc.log
# fi
# 
# 
# FILTER="gawk -f $script_home/rtl-filter.awk"
# [ "$VERBOSE" == "true" ] && FILTER="cat"
# 
# # echo VERBOSE=$VERBOSE
# # echo FILTER=$FILTER
# 
# nobuf='stdbuf -oL -eL'
# 
# # FIXME use mymake below in place of various "make" sequences
# function mymake {
#     make_flags=$1; target=$2; log=$3
#     unset FAIL
#     nobuf='stdbuf -oL -eL'
#     # make mentor-calibre-drc < /dev/null
#     echo make $make_flags $target
#     make $make_flags $target < /dev/null \
#         |& $nobuf tee -a ${log} \
#         |  $nobuf gawk -f $script_home/post-rtl-filter.awk \
#         || FAIL=1
#     if [ "$FAIL" ]; then
#         echo ""
#         sed -n '/^====* FAILURES/,$p' $log
#         $exit_unless_verbose
#     fi
#     unset FAIL
# }
# 
# # So. BECAUSE makefile files silently (and maybe some other good
# # reasons as well), we now do (at least) two stages of build.
# # "make rtl" fails frequently, so that's where we'll put the
# # first break point
# #
# echo "--- MAKE RTL"
# make_flags=""
# [ "$VERBOSE" == "true" ] && make_flags="--ignore-errors"
# mymake "$make_flags" rtl mcdrc.log|| $exit_unless_verbose
# 
# if [ ! -e *rtl/outputs/design.v ] ; then
#     echo ""; echo ""; echo ""
#     echo "***ERROR Cannot find design.v, make-rtl musta failed"
#     echo ""; echo ""; echo ""
#     $exit_unless_verbose
# else
#     echo ""
#     echo Built verilog file *rtl/outputs/design.v
#     ls -l *rtl/outputs/design.v
#     echo ""
# fi
# 
# # For pad_frame, want to check bump connections and FAIL if problems
# if [ "$module" == "pad_frame" ] ; then
#   echo "--- MAKE SYNTHESIS"
#   make_flags="--ignore-errors"
#   target="synopsys-dc-synthesis"
#   mymake "$make_flags" $target make-syn.log || $exit_unless_verbose
# 
#   echo "--- MAKE INIT"
#   make_flags=""
#   [ "$VERBOSE" == "true" ] && make_flags="--ignore-errors"
#   target="cadence-innovus-init"
#   echo "exit_unless_verbose='$exit_unless_verbose'"
#   mymake "$make_flags" $target make-init.log || $exit_unless_verbose
# 
#   # Check for errors
#   log=make-init.log
#   echo ""
# 
#   grep '^\*\*ERROR' $log
#   echo '"not on Grid" errors okay (for now anyway) I guess'
#   # grep '^\*\*ERROR' $log | grep -vi 'not on grid' ; # This throws an error when second grep succeeds!
#   n_errors=`grep '^\*\*ERROR' $log | grep -vi 'not on Grid' | wc -l` || $PASS
#   echo "Found $n_errors non-'not on grid' errors"
#   test "$n_errors" -gt 0 && echo "That's-a no good! Bye-bye."
#   test "$n_errors" -gt 0 && exit 13
#   # exit
# fi
# 
# # Trying something new
# ########################################################################
# # New tests, for now trying on Tile_PE and Tile_MemCore only
# # TODO: pwr-aware-gls should be run only if pwr_aware flag is 1
# if [ "$module" == "Tile_PE" ] ; then
# 
# #     echo "--- DEBUG TIME"
# #     set -x
# #     pwd
# #     ls conf* || echo not there yet
# #     set +x
# # 
# #     echo "--- MAKE LVS"
# #     make mentor-calibre-lvs
# # 
# #     echo "--- MAKE GLS"
# #     make pwr-aware-gls
# 
#     for step in $build_sequence; do
#         echo "--- MAKE $step"
#         [ "$step" == "synthesis" ] && step="synopsys-dc-synthesis"
#         make $step || exit 13
#     done
#     exit 0
# fi
# 
# if [ "$module" == "Tile_MemCore" ] ; then
# 
# #     echo "--- MAKE LVS"
# #     make mentor-calibre-lvs
# # 
# #     echo "--- MAKE GLS"
# #     make pwr-aware-gls
# 
#     for step in $build_sequence; do
#         echo "--- MAKE $step"
#         [ "$step" == "synthesis" ] && step="synopsys-dc-synthesis"
#         make $step || exit 13
#     done
#     exit 0
# fi
# 
# ########################################################################
# 
# echo "--- MAKE DRC"
# make_flags=''
# [ "$VERBOSE" == "true" ] && make_flags="--ignore-errors"
# if [ "$module" == "pad_frame" ] ; then
#     target=init-drc
#     # FIXME Temporary? ignore-errors hack to get past dc synthesis assertion errors.
#     make_flags='--ignore-errors'
# elif [ "$module" == "icovl" ] ; then
#     target=drc-icovl
#     # FIXME Temporary? ignore-errors hack to get past dc synthesis assertion errors.
#     make_flags='--ignore-errors'
# else
#     target=mentor-calibre-drc
# fi
# 
# unset FAIL
# nobuf='stdbuf -oL -eL'
# # make mentor-calibre-drc < /dev/null
# log=mcdrc.log
# echo make $make_flags $target
# make $make_flags $target < /dev/null \
#   |& $nobuf tee -a ${log} \
#   |  $nobuf gawk -f $script_home/post-rtl-filter.awk \
#   || FAIL=1
# 
# # Display pytest failures in detail
# # =================================== FAILURES ===========...
# # ___________________________________ test_2_ ____________...
# # mflowgen-check-postconditions.py:24: in test_2_
# if [ "$FAIL" ]; then
#     echo ""
#     sed -n '/^====* FAILURES/,$p' $log
#     $exit_unless_verbose
# fi
# unset FAIL
# 
# # Error summary. Note makefile often fails silently :(
# echo "+++ ERRORS"
# echo ""
# echo "First twelve errors:"
# grep -i error ${log} | grep -v "Message Sum" | head -n 12 || echo "-"
# 
# echo "Last four errors:"
# grep -i error ${log} | grep -v "Message Sum" | tail -n 4 || echo "-"
# echo ""
# 
# # Did we get the desired result?
# unset FAIL
# ls -l */drc.summary > /dev/null || FAIL=1
# if [ "$FAIL" ]; then
#     echo ""; echo ""; echo ""
#     echo "Cannot find drc.summary file. Looks like we FAILED."
#     echo ""; echo ""; echo ""
#     echo "tail ${log}"
#     tail -100 ${log} | egrep -v '^touch' | tail -8
#     $exit_unless_verbose
# fi
# # echo status=$?
# echo "DRC SUMMARY FILE IS HERE:"
# echo `pwd`/*/drc.summary
# 
# echo ""; echo ""; echo ""
# echo "FINAL RESULT"
# echo "------------------------------------------------------------------------"
# 
# # Given a file containing final DRC results in this format:
# # CELL Tile_PE ................................ TOTAL Result Count = 4
# #     RULECHECK OPTION.COD_CHECK:WARNING ...... TOTAL Result Count = 1
# #     RULECHECK M3.S.2 ........................ TOTAL Result Count = 1
# #     RULECHECK M5.S.5 ........................ TOTAL Result Count = 1
# # --------------------------------------------------------------------
# # Print the results to a temp file prefixed by summary e.g.
# # "2 error(s), 1 warning(s)"; return name of temp file
# function drc_result_summary {
#     # Print results to temp file 1
#     f=$1; i=$2
#     tmpfile=/tmp/tmp.test_pe.$USER.$$.$i; # echo $tmpfile
#     # tmpfile=`mktemp -u /tmp/test_module.XXX`
#     sed -n '/^CELL/,/^--- SUMMARY/p' $f | grep -v SUMM > $tmpfile.1
# 
#     # Print summary to temp file 0
#     n_checks=`  grep   RULECHECK        $tmpfile.1 | wc -l`
#     n_warnings=`egrep 'RULECHECK.*WARN' $tmpfile.1 | wc -l`
#     n_errors=`  expr $n_checks - $n_warnings`
#     echo "$n_errors error(s), $n_warnings warning(s)" > $tmpfile.0
# 
#     # Assemble and delete intermediate temp files
#     cat $tmpfile.0 $tmpfile.1 > $tmpfile
#     rm  $tmpfile.0 $tmpfile.1
#     echo $tmpfile
# }
# 
# 
# # Expected result
# res1=`drc_result_summary $script_home/expected_result/$module exp`
# echo -n "--- EXPECTED "; cat $res1
# n_errors_expected=`awk 'NF=1{print $1; exit}' $res1`
# echo ""
# 
# # Actual result
# res2=`drc_result_summary */drc.summary got`
# echo -n "--- GOT..... "; cat $res2
# n_errors_got=`awk 'NF=1{print $1; exit}' $res2`
# echo ""
# 
# # Diff
# echo "+++ Expected $n_errors_expected errors, got $n_errors_got errors"
# 
# ########################################################################
# # PASS or FAIL?
# if [ $n_errors_got -le $n_errors_expected ]; then
#     rm $res1 $res2
#     echo "GOOD ENOUGH"
#     echo PASS; exit 0
# else
#     # Need the '||' below or it fails too soon :(
#     diff $res1 $res2 | head -40 || echo "-----"
#     rm $res1 $res2
# 
#     # echo "TOO MANY ERRORS"
#     # echo FAIL; $exit_unless_verbose
# 
#     # New plan: always pass if we get this far
#     echo "NEW ERRORS but that's okay we always pass now if we get this far"
#     echo PASS; exit 0
# fi
# 
# 
# # OLD environment build
# # if [ "$USER" == "buildkite-agent" ]; then
# #     echo "--- REQUIREMENTS"
# # 
# #     # /var/lib/buildkite-agent/env/bin/python3 -> python
# #     # /var/lib/buildkite-agent/env/bin/python -> /usr/local/bin/python3.7
# # 
# #     USE_GLOBAL_VENV=false
# #     if [ "$USE_GLOBAL_VENV" == "true" ]; then
# #         # Don't have to do this every time
# #         # ./env/bin/python3 --version
# #         # ./env/bin/python3 -m virtualenv env
# #         source $HOME/env/bin/activate; # (HOME=/var/lib/buildkite-agent)
# #     else
# #         echo ""; echo "NEW PER-STEP PYTHON VIRTUAL ENVIRONMENTS"
# #         # JOBDIR should be per-buildstep environment e.g.
# #         # /sim/buildkite-agent/builds/bigjobs-1/tapeout-aha/
# #         JOBDIR=$BUILDKITE_BUILD_CHECKOUT_PATH
# #         pushd $JOBDIR
# #           /usr/local/bin/python3 -m virtualenv env ;# Builds "$JOBDIR/env" maybe
# #           source $JOBDIR/env/bin/activate
# #         popd
# #     fi
# #     echo ""
# #     echo PYTHON ENVIRONMENT:
# #     for e in python python3 pip3; do which $e || echo -n ''; done
# #     echo ""
# #     pip3 install -r $garnet/requirements.txt
# # fi
# # 
# # THIS IS NOW PART OF REQUIREMENTS_CHECK.SH
# # # Check for memory compiler license
# # if [ "$module" == "Tile_MemCore" ] ; then
# #     if [ ! -e ~/.flexlmrc ]; then
# #         cat <<EOF
# # ***ERROR I see no license file ~/.flexlmrc
# # You may not be able to run e.g. memory compiler
# # You may want to do e.g. "cp ~ajcars/.flexlmrc ~"
# # EOF
# #     else
# #         echo ""
# #         echo FOUND FLEXLMRC FILE
# #         ls -l ~/.flexlmrc
# #         cat ~/.flexlmrc
# #         echo ""
# #     fi
# # fi
# # 
# # # Lots of useful things in /usr/local/bin. coreir for instance ("type"=="which")
# # # echo ""; type coreir
# # export PATH="$PATH:/usr/local/bin"; hash -r
# # # type coreir; echo ""
# # 
# # # Set up paths for innovus, genus, dc etc.
# # source $garnet/.buildkite/setup.sh
# # source $garnet/.buildkite/setup-calibre.sh
# # 
# # # OA_HOME weirdness
# # echo "--- UNSET OA_HOME"
# # echo ""
# # echo "buildkite (but not arm7 (???)) errs if OA_HOME is set"
# # echo "BEFORE: OA_HOME=$OA_HOME"
# # echo "unset OA_HOME"
# # unset OA_HOME
# # echo "AFTER:  OA_HOME=$OA_HOME"
# # echo ""
# # 
# # # Oop "make rtl" (among others maybe) needs GARNET_HOME env var
# # export GARNET_HOME=$garnet
# 
# # OLD - check failed to find the targeted bug...
# #     # Quick check of adk goodness maybe
# #     iocells_bk=./tsmc16/stdview/iocells.lef
# #     iocells_sr=/sim/steveri/mflowgen/adks/tsmc16/stdview/iocells.lef
# #     pwd
# #     ls -l $iocells_bk $iocells_sr
# #     if diff $iocells_bk $iocells_sr; then
# #         echo YESSSSS maybe we got the right adk finally
# #         echo 'note btw this is the "right" one in that this is the one that is supposed to fail...'
# #     else
# #         echo NOOOOOO looks like we continue to screw up with the adks
# #         exit 13
# #     fi
# #     set +x
