#!/usr/bin/env bash

# workspace_switcher.sh: slow, crude tool to visualize current X11
# workspaces with their ID. Meant to be called from a shortcut key.
# call with cmdline arg $1: "nolabel" for a slight speed-up
# TODOs:
# Rewrite in a context with direct access to the framebuffer?
# Not need to switch workspaces to snap them
# Combine key that calls this script with the one that switches to workspace
# i.e.; flag-key + tab (tab, tab...), etc,...

ROWS=2
DISPLAY_SLEEP=5.67    # in sec, just long-enough to see popup b4 it's killed
LABEL_RATIO=0.75      # for each workspace snap
# fit inside largest display while efficiently scaling
DISPLAY_RATIO=0.2683  # TODO: dynamically calc?

DEPS='awk bc magick mktemp wmctrl xrandr'  # TODO: versions of these (does it matter)?

usage()
{
  echo -e "usage: `basename $0` [nolabel]\n\tdependencies: ${DEPS}"
  exit 1
}
# check dependencies
for d in $DEPS
do
  which $d > /dev/null
  if [ $? -ne 0 ]
  then
    echo failed to find dependencies
    usage
  fi
done

floorCalcInt()
{
  echo "scale=0; (${1}) / 1" | bc
}
getOutputDims()
{
  # for all outputs: name => w h offset_x offset_y
  # assumes xrandr output like:
  # DP1 connected primary 1920x1200+1360+0 (normal left inverted right x axis y axis) 520mm x 330mm
  #    1920x1200     59.95*+
  out_file="$1"
  xrandr -q \
  | awk '/connected/ {
        dn=$1; 
        if($3=="primary") geo=$4;
        else  geo=$3; 
        split(geo,ga,"+");
        res=ga[1];ox=ga[2];oy=ga[3];
        split(res,ra,"x");w=ra[1];h=ra[2]
    } /\*/ {
      print dn,w,h,ox,oy
    }' > "$out_file"
}
getLargestDisplay()
{
  dims_file="$1"
  largest=0
  largest_name=
  while read l
  do
    dims=($l)
    dn=${dims[0]}
    w=${dims[1]}
    h=${dims[2]}
    p=$(($w * $h))
    if [ $p -ge $largest ]
    then
      largest=$p
      largest_name=$dn
    fi
  done < "$dims_file"
  grep $largest_name "$dims_file"
}
getScreenSize()
{
  # assumes xrandr output like:
  # Screen 0: minimum 8 x 8, current 3840 x 1200, maximum 32767 x 32767
  # ...
  xrandr --current \
  | head -n1 \
  | cut -d, -f2 \
  | cut -d' ' -f 3,5 \
  | tr ' ' x
}

# capture current state 
screen_size=`getScreenSize`
dims_file=`mktemp`
getOutputDims "$dims_file"
out_display_dims=(`getLargestDisplay "$dims_file"`)
rm -v "$dims_file"
out_display=${out_display_dims[0]}
x_offset=${out_display_dims[3]}
y_offset=${out_display_dims[4]}
if [ -z "$x_offset" -o -z "$screen_size" -o -z "$y_offset" ]
then
  echo failed to get current state
  usage
fi
workspace_info=`wmctrl -d`
cnt_workspaces=$(echo "${workspace_info}" | wc -l)
init_workspace=`echo "${workspace_info}" | grep '\*' | cut -d' ' -f1`

# snapshot all screens
cols=$(($cnt_workspaces / $ROWS))
declare -a shots
screen_w=`echo $screen_size | cut -dx -f1`
screen_h=`echo $screen_size | cut -dx -f2`
label_h=`floorCalcInt "${screen_h} * ${LABEL_RATIO}"`

for i in `seq 0 $(($cnt_workspaces-1))`
do
  wmctrl -s $i
  shot_file="/tmp/${mn}.${i}.rgb"
  shots[$i]=$shot_file
  import -window root $shot_file
  [ "$1" = "nolabel" ] && continue
  magick -size $screen_size -gravity Center $shot_file -pointsize $label_h -fill red -annotate 0 $(($i+1)) $shot_file
done
wmctrl -s $init_workspace

# display snaps as tiles
snap_w=`floorCalcInt "${screen_w} * ${DISPLAY_RATIO}"`
snap_h=`floorCalcInt "${screen_h} * ${DISPLAY_RATIO}"`
snap_ind=0

for row in 0 1; do
  for col in 0 1; do
    _x_offset=$(($snap_w * $col + x_offset))
    _y_offset=$(($snap_h * $row))
    display -size $screen_size -resize "x${snap_h}" -geometry +$_x_offset+$_y_offset ${shots[$snap_ind]}  &
    snap_ind=$(($snap_ind + 1))
done; done

# wait a second,.. where are we going?...
sleep $DISPLAY_SLEEP
killall display
rm -v /tmp/workspace_switcher.sh.*

#wmctrl -m | awk '/Name/ {print $NF}' | grep -q Fluxbox || usage
#ristretto -f $final_shot_file
#xprop

