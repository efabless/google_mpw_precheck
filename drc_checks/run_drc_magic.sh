#!/bin/bash
# SPDX-FileCopyrightText: 2020 Efabless Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0

# To call: ./run_drc_magic.sh <target_path> <design_name> <pdk_root> <output_path>

export TARGET_DIR=${TARGET_DIR:-$1}
export DESIGN_NAME=${DESIGN_NAME:-$2}
export PDK_ROOT=${PDK_ROOT:-$3}
export OUT_DIR=${OUT_DIR:-$4}
export SCRIPTS_ROOT=${SCRIPTS_ROOT:-${5:-$(pwd)}}

echo "SCRIPTS_ROOT is "
echo $SCRIPTS_ROOT

mkdir -p "$OUT_DIR"
echo "Running Magic..."
cp /usr/local/bin/tech-files/sky130A.magicrc $TARGET_DIR/.magicrc
export MAGTYPE=mag
cd $TARGET_DIR
ulimit -c unlimited

SRAM_MODULES=( sky130_sram_1kbyte_1rw1r_32x256_8
    sky130_sram_1kbyte_1rw1r_8x1024_8
    sky130_sram_2kbyte_1rw1r_32x512_8
    sky130_sram_4kbyte_1rw1r_32x1024_8
    sky130_sram_8kbyte_1rw1r_32x2048_8
    sram_1rw1r_32_256_8_sky130 )

if zgrep sram $DESIGN_NAME.gds ;
then
    export HAS_SRAM=1
    for SRAM in ${SRAM_MODULES[@]};
    do
        if [[ $(zgrep $SRAM $DESIGN_NAME.gds) ]]
        then
            export SRAM=$SRAM
            echo "module has "
            echo $SRAM
            break
        fi
    done
fi

magic \
    -noconsole \
    -dnull \
    $SCRIPTS_ROOT/magic_drc_check.tcl \
    </dev/null \
    |& tee "$OUT_DIR/magic_drc.log"

TEST=$OUT_DIR/$DESIGN_NAME.magic.drc

crashSignal=$(find $TEST)
if ! [[ $crashSignal ]];
then
    echo "DRC Check FAILED";
    exit -1;
fi


Test_Magic_violations=$(grep "COUNT: " $TEST -s | tail -1 | sed -r 's/[^0-9]*//g')
if ! [[ $Test_Magic_violations ]];
then
    Test_Magic_violations=-1;
fi
if [ $Test_Magic_violations -ne -1 ];
then
    Test_Magic_violations=$(((Test_Magic_violations+3)/4));
fi

echo "Test # of DRC Violations: $Test_Magic_violations"

if [ 0 -ne $Test_Magic_violations ]; then
    echo "[Info] Converting errors to RDB format..."
    python3 $SCRIPTS_ROOT/converters/magic_drc_to_rdb.py \
        --magic_drc_in $OUT_DIR/$DESIGN_NAME.magic.drc \
        --rdb_out $OUT_DIR/$DESIGN_NAME.magic.rdb
    echo "[Info] Converted errors in RDB format"

    echo "[Info] Converting errors to Magic Readable TCL format..."
    python3 $SCRIPTS_ROOT/converters/magic_drc_to_tcl.py \
        --input_file $OUT_DIR/$DESIGN_NAME.magic.drc \
        --output_file $OUT_DIR/$DESIGN_NAME.magic.drc.tcl
    echo "[Info] Converted errors to Magic Readable TCL format"

    echo "[Info] Converting errors to TritonRoute DRC format..."
    python3 $SCRIPTS_ROOT/converters/magic_drc_to_tr_drc.py \
        --input_file $OUT_DIR/$DESIGN_NAME.magic.drc \
        --output_file $OUT_DIR/$DESIGN_NAME.tr.drc
    echo "[Info] Converted errors to TritonRoute DRC format"

    echo "[Info] Converting errors to Klayout XML format..."
    python3 $SCRIPTS_ROOT/converters/tr2klayout.py \
        --input $OUT_DIR/$DESIGN_NAME.tr.drc \
        --output $OUT_DIR/$DESIGN_NAME.klayout.xml \
        --design-name $DESIGN_NAME
    echo "[Info] Converted errors to Klayout XML format"

    echo "DRC Check FAILED";

    exit -1;
fi

echo "DRC Check Passed"
exit 0
