#!/bin/bash

#set -e
set -u

media_files_extensions="mp3|mp4|avi|m4a|opus|webm|wav|flac|alac|aiff"
tag_comment=0
tag_filename=0
debug=0
output_type=2
wrote_csv_header=0
full_output=0
field_separator="|"
subfield_separator="_"
do_uniq=1
justify=80

run_tool1=1
run_tool2=1
run_tool3=1

do_vbr=0
do_recursive=1
only_do_find=0


# main operations follows
do_operation="check_headers"
do_raw_mp3guessenc=0

file_out_csv="mp3_headers.csv"
file_out_raw="mp3_headers.raw"
    
save_output_files=1
dump_raw_tools=0


#####

argc=0
declare -a argv
function add_argv()
{
	(( argc ++ ))		|| true
	argv[$argc]="$1"
}


display_help()
{
  echo "

check encoder of files, using several tools
usage: `basename $0` file1 [file2]


operation:
  --headers         check mp3guessenc values (default)
  --ffprobe_json    dump ffprobe
  --encoder         only guess encoder (3x tools)
  
options:
  --fast      do NOT run VBR check
  --slow      run VBR check
  
  --raw|-r    dump raw mp3guessenc / mediainfo output
  -o          save output files in folder  (CSV, RAW)  
    
  --no_recursive    skip recursive 
  --recursive       recursive (still neeeds '.')    
    
old options:    
  -j     size to justify one-liner output
  --uniq_tags     filter out repeated tags    (default)
  --repeated_tags     show repeated tags 
  
sub-tools:
  --ffmpeg|--ffprobe    ONLY run ffprobe 
  --mp3guessenc         ONLY run mp3guessenc
  --mediainfo           ONLY run mediainfo

  
 "
  exit 1

}

function pass()
{
  local nop="nop"
}


#
# Syntactic sugar to declare global variables explicitly
#
# locals are used:
#   primary parameters into functions (readonly)
# 
# globals are used:
#   return variables
#   secondary parameters into functions (convenience)
#
# 
# template of function:
#   function swap()
#   {
#      local param1="$1"
#      local param2="$2"
#
#      global ret1
#      global ret2
#  
#      ret1="$param2"
#      ret2="$param1"
#   }

#   function do_outer()
#   {
#      global ret1
#      global ret2
#       
#      ret1=""
#      ret2=""
#
#      do_inner "aaa" "bbb"
#      echo "The result was: $ret1 / $ret2"     
#   }
#
#
#
#
function global()
{
  local var="$1"
  
}


function echo_var()
{
  local var="$1"
  echo "${var} -> ${!var}"
}



function assert_command_exists ()
{
	local FILE="$1"
	local RET=0
	check_command_exists "$FILE"  || RET=1

	if [ $RET -ge 1 ]; then
		echo_var PATH
		die "assert_command_exists: '${1:-}' command was not found"
	fi

	return 0
}

#
# this code supports broken "which" of sun machines
# $1 - command name
#
# returns 1 of error
# returns 0 if Ok
function check_command_exists ()
{
	local FILE="`which "${1:-}" `"
		
	if [[ -z "$FILE" || ! -r "$FILE" ]]; then
		return 1
	else
		return 0
	fi
}


#
# $@ - tools names
#
function require_tools ()
{
	local FILE=""

	for FILE in "$@" ; do
		assert_command_exists "$FILE"
	done
}


function echo_stderr ()
{
	echo -e "$@" >&2
}



#
# Generic die function. 
# Shows a message, then exits the program
#
function die()
{
	set +x
  echo_stderr ""
	echo_stderr "********************"
	echo_stderr "ERROR: ${1:-}"
	echo_stderr "********************"
	echo_stderr ""
	
  
	exit 99
}



#
# Generic die function. 
# Shows a message, then exits the program
#
function die()
{
	set +x
  echo_stderr ""
	echo_stderr "********************"
	echo_stderr "ERROR: ${1:-}"
	echo_stderr "********************"
	echo_stderr ""
	
  
	exit 99
}




function do_sleep()
{
  local time="$1"
  echo "slepping $time seconds"
  sleep "$time"
}



function die_if_failure()
{
  local ret="$1"
  if [ "$ret" -ge 1 ]; then
    echo "exiting."
    exit "$ret"
  fi
}

# library functions follow

#
# A.B.C -> C
#
function extension()
{
	#echo "${1##*.}"
	echo "$1" | awk -F . '{print $NF}'

}

function extension_lower()
{
	#echo "${1##*.}"
	echo "$1" | awk -F . '{print $NF}' | tr '[:upper:]' '[:lower:]'
}


#
# A.B.C -> A.B
#
function remove_extension()
{
	echo "${1%.*}"
}

#
# A.B.C X -> A.B - X.C
#
function add_posttag()
{
	local FILE="$1"
	local ADD="$2"
	local SEP="${3:- - }"

	local B="`remove_extension "${FILE}"`"
	local E="`extension "${FILE}"`"

	echo "${B}${SEP}${ADD}.${E}"
}

function do_uniq()
{
  if [ $do_uniq -ge 1 ]; then 
    uniq 
  else
    cat -
  fi

}

function join_seperator()
{
  #sed 's/ $//' | 
  sed 's/ /\n/g' | paste -s -d "$field_separator"
}

function array_to_csv () 
{
  # https://stackoverflow.com/questions/11180714/how-to-iterate-over-an-array-using-indirect-reference
  #https://mywiki.wooledge.org/BashFAQ/005  
  #IFS=/; echo "${!arr[*]}"; unset IFS

  local arrayname="$1"
  local tmp="$arrayname[@]"
  local array=( "${!tmp}" )
  local FS="$field_separator"
  local var
  

  local quote=""
  local do_quote=0
  
  # Print each element enclosed in quotes and separated by $FS
  if [ $do_quote -ge 1 ]; then
    printf -v var "\"%s\"$FS"  "${array[@]}"
  else
    printf -v var "%s$FS"  "${array[@]}"
  
  fi
  
  # Chop trailing $FS
  var=${var%$FS}
  
  tee_to_file=0
  
 
  echo "$var" | if [ "$tee_to_file" -ge 1 ]; then
    tee -a "$out_csv1"
  else
    cat -
  fi
}


function last_field_or_unk()
{
  to_unk="$1"
  
  awk '{print $NF}' | awk -v to_unk="$to_unk" '{if(NF){A=1}} {if(NF){print }} END{if(A==0){print to_unk }}'

}


function massage_output()
{
  if [ $full_output -ge 1 ]; then
    cat -
    return 
  fi

  egrep -i "encoder|librar" | do_uniq | \
  if [ $output_type -eq 0 ]; then
    cat - 
  else
    cat - | awk '{print $NF }' | do_uniq | paste -s -d "$subfield_separator" | last_field_or_unk
  fi
}


# sub-tools to check:
# sudo apt-get install ffmpeg lltag eyed3 mp3info id3v2 libimage-exiftool-perl libid3-tools id3tool
# https://askubuntu.com/questions/226773/how-to-read-mp3-tags-in-shell



function run_tool()
{
  local file="$1"
  local tool="$2"

  shift 2
  
  if [ $output_type -eq 0 ]; then
    echo ""
    echo "********************************"
    echo "Running ${tool}:"
  fi
  
  "$tool" "$@" "$file" 2>&1 | massage_output #"$tool"
}


function sed_out()
{
  # TODO: warn if seperator appears in string!
  local what
  what="${1:-}"

  if [ "$what" == "" ]; then
    cat -
  else
    sed "s|${what}||"
  fi
}


function get_line_field()
{
  to_grep="$1"
  
  to_sed="${2:-}"
  to_unk="${3:-UNK}"

  egrep "$to_grep" | sed_out "$to_sed" | last_field_or_unk "$to_unk"
}


function see_if_line_present()
{
  
  to_grep="$1"

  filter="`egrep "$to_grep" | head -n 1 `"
  if [ "$filter" == "" ]; then
    echo "no"
  else
    echo "yes"
  fi
}


function do_guess_encoder()
{
  local file="$1"
  global csv_header 
  global tags

  ####
  tag1=""
  tag2=""
  tag3=""
  
  if [ "$run_tool1" -ge 1 ]; then
    tag1="`run_tool "$file" ffprobe -hide_banner -loglevel verbose `"
  fi
  
  if [ "$run_tool2" -ge 1 ]; then
    tag2="`run_tool "$file" mp3guessenc -s `"
  fi
 
  if [ "$run_tool3" -ge 1 ]; then
    tag3="`run_tool "$file" mediainfo `"
  fi

  tags=()

  tags+=( "${tag1}" )
  tags+=( "${tag2}" )
  tags+=( "${tag3}" )

  csv_header=( "ffprobe" "mp3guessenc"  "mediainfo" )
}



function do_check_headers()
{
  local file="$1"
  global csv_header 
  global tags
  
  ### run tools
  raw_dd="` dd if="$file" bs=400000 count=1 2>/dev/null | strings | egrep "^Info$|^Xing$|^VBRi$" `"
 
  mp3guessenc="`mp3guessenc -v "$file" `"  

  mp3guessenc_errors="`mp3guessenc -p "$file" `"  

  
  if [ "$do_vbr" -ge 1 ]; then
    mediainfo="`mediainfo "$file" `"
  else
    mediainfo=""
  fi
  #eyeD3 -P lameinfo r.mp3  2>/dev/null | grep -a -c nogap

  
  if [ "$dump_raw_tools" -ge 1 ]; then
    mp3guessenc_full="`mp3guessenc "$file" `"  


  (
    echo "

*************
FILE: $file

MEDIAINFO:
$mediainfo
    

MP3GUESSENC FULL:
$mp3guessenc_full


RAW DD:
$raw_dd
*************


"
    ) | save_output "$file_out_raw"
    
  fi
  
  ### massage outputs
  sep="___"


  raw_dd_info="`echo "$raw_dd" | see_if_line_present "^Info$" `"
  raw_dd_xing="`echo "$raw_dd" | see_if_line_present "^Xing$" `"
  raw_dd_vbri="`echo "$raw_dd" | see_if_line_present "^VBRi$" `"
  raw_dd_id3v2="`echo "$raw_dd" | see_if_line_present "^ID3$" `"

  raw_dd_common="` echo "$raw_dd" | paste -s -d "_" `"
  if [ "$raw_dd_common" == "" ]; then
    raw_dd_common_any="no"
  else
    raw_dd_common_any="yes"
  fi
  
  
  first_frame_bad="`echo "$mp3guessenc_errors" | see_if_line_present "^Unexpected data at 0" `"
 
  
  xing_tag_present="`echo "$mp3guessenc" | see_if_line_present "^Xing tag detected" `"

  lame_tag_present="`echo "$mp3guessenc" | get_line_field "^  Lame tag"  "" "no"`"
  lame_tag_valid="`echo "$mp3guessenc"   | get_line_field "^  Tag verification " `"
  encoder_delay="`echo "$mp3guessenc"    | get_line_field "^  Encoder delay" "samples" `"
  encoder_padding="`echo "$mp3guessenc"  | get_line_field "^  Encoder padding" "samples" `"
  nogap_continued="`echo "$mp3guessenc"  | get_line_field "^  nogap continued" `"
  nogap_continuation="`echo "$mp3guessenc"  | get_line_field "^  nogap continuation" `"
  
  bitrate_mode="`echo "$mediainfo"       | get_line_field "^Bit rate mode" `"
  bitrate_value="`echo "$mediainfo"      | get_line_field "^Bit rate     " "kb/s" `"

  
  #### derived fields
  # https://github.com/digital-dj-tools/dj-data-converter/issues/3
  
  highest_tag_present="unk"
  case="unk"
  problem="unk"

  if [ "$first_frame_bad" == "yes" ]; then
    # AKA null streams
    highest_tag_present="null"
    if [ $raw_dd_common_any == "no" ]; then
      case="E"
    else
      case="F"
    fi
        
    
  elif [ "$xing_tag_present" == "no" ]; then
    highest_tag_present="none"
    case="A"
    
  elif [ "$xing_tag_present" == "yes" ]; then
  
    if [ "$lame_tag_present" == "no" ]; then
      highest_tag_present="xing"
      case="B"
      
    elif [ "$lame_tag_present" == "yes" ]; then
      highest_tag_present="lame"
      
      if [ "$lame_tag_valid" == "passed" ]; then
        case="D"
        
      elif [ "$lame_tag_valid" == "failed" ]; then
        case="C"
        
      else
        die "unk lame_tag_valid: $lame_tag_valid"
      fi
    fi
  fi 
  
  
  
  case "$case" in
  A|D|E)
    correction="0"
    problem="no"
    ;;
  B|C|F)
    correction="26"
    problem="yes"
    ;;
   
  *)
    correction="unk"
    problem="unk"
    ;;
  esac
  
  tags=()

  tags+=( "$problem" )
  tags+=( "$case" )
  tags+=( "$correction" )

  tags+=( "$sep" )
  
  tags+=( "$first_frame_bad" )
  
  tags+=( "$sep" )
  
  tags+=( "$raw_dd_common" )
  tags+=( "$raw_dd_xing" )
  tags+=( "$raw_dd_info" )
  tags+=( "$raw_dd_vbri" )
  tags+=( "$raw_dd_id3v2" )
  
  tags+=( "$sep" )
  
  tags+=( "$highest_tag_present" )
  tags+=( "$xing_tag_present" )
  tags+=( "$lame_tag_present" )
  tags+=( "$lame_tag_valid" )
  

  tags+=( "$sep" )

  tags+=( "$encoder_delay" )
  tags+=( "$encoder_padding" )
  tags+=( "$nogap_continued" )
  tags+=( "$nogap_continuation" )

  tags+=( "$sep" )
  
  tags+=( "$bitrate_mode" )
  tags+=( "$bitrate_value" )

  csv_header=( "problem" "case" "correction" "sep1" \
    "first_frame_bad" "sep2" \
    \
    "raw_dd_common" "raw_dd_xing" "raw_dd_info"  "raw_dd_vbri"  "raw_dd_id3v2"  "sep3" \
    \
     "highest_tag"  "xing_present"  "lame_present" "lame_valid"  "sep4" \
    "enc_delay" "enc_padding" "nogap_continued" "nogap_continuation"  "sep5" \
    "bitrate_mode" "bitrate_value" )
    
}




function get_tags()
{
  local file="$1"
  global tags
  global csv_header
  
  if [ "$do_operation" == "check_headers" ]; then
    do_check_headers "$file"
    
  elif [ "$do_operation" == "guess_encoder" ]; then
    do_guess_encoder "$file"
    
  else
    die "unk oper"
    
  fi

  if [ "$do_raw_mp3guessenc" -ge 1 ]; then
    return
  fi
  
  
  #####
  csv_header+=("file")
  tags+=("$file")
  
  
  ##########
  if [ $wrote_csv_header -eq 0 ]; then
    array_to_csv   csv_header | save_output "$file_out_csv"

    wrote_csv_header=1
    
  fi
    
  array_to_csv tags | save_output "$file_out_csv"
  
}


function save_output()
{
  local file_out="$1"

  if [ $save_output_files -ge 1 ]; then
    tee -a "$file_out"
  else
    cat -
  fi
}


function test_1_file()
{
  local file="$1"

  if [ $only_do_find -ge 1 ]; then
    echo "$file" 
    return
  fi    
  
  if [ "$do_operation" == "ffprobe_json" ]; then
    ffprobe -v error -print_format json -show_format -show_streams  "$file"
    echo ","
    return
  fi
  

  get_tags "$file" 
   
}


#####
#####

require_tools "mpg123"  "mp3guessenc" "ffprobe" "ffmpeg" "mediainfo"  

    
while [ "$#" -ge 1 ]; do
  case "$1" in
  -d|--debug|--d)
    debug=1
    set -x
    ;;
    
  -dd|--dd)
    debug=2
    set -x
    ;;
  

    
  -C)
    wrote_csv_header=1
    ;;
    
  --repeated_tags)
    do_uniq=0
    ;;
    
  --uniq_tags)
    do_uniq=1
    ;;

  -j)
    justify="$2"
    shift
    ;;
    
  --tag_metadata|--tag_composer)
    tag_comment=1
    ;;
    
  --tag_filename)
    tag_filename=1
    ;;

    
  --ffmpeg|--ffprobe)
    run_tool1=1
    run_tool2=0
    run_tool3=0
    do_operation="guess_encoder"

    ;;
    
  --mp3guessenc)
    run_tool1=0
    run_tool2=1
    run_tool3=0
    do_operation="guess_encoder"

    ;;

  --mediainfo)
    run_tool1=0
    run_tool2=0
    run_tool3=1
    do_operation="guess_encoder"
    ;;


  --no_vbr|+v|--fast|-f)
    do_vbr=0
    ;;

  --vbr|--slow|-s)
    do_vbr=1
    ;;
    
  --recursive|-R)
    do_recursive=1
    ;;

  --no_recursive|+R)
    do_recursive=0
    ;;
    
  --find|--only_find)
    only_do_find=1
    
    ;;

    
  --raw|-r)
    dump_raw_tools=1
    do_operation="check_headers"
    ;;

  --headers)
    dump_raw_tools=0
    do_operation="check_headers"
    ;;

  
  --ffprobe_json|-J)
    do_operation="ffprobe_json"
    ;;
  
 
  -o)
    save_output_files=1
    ;;
  
  
  -h)
    display_help
    ;;
    
  -*)  
    die "unk argument: $1"
    ;;
    
  *)
    add_argv "$1"
    ;;
    
  esac
  
  shift
done



if [ "$argc" -eq 0 ]; then
  echo "Error: no files specified"
  echo ""
  display_help
fi

if [ "$only_do_find" -ge 1 ]; then
  save_output_files=0
fi


if [ $do_recursive -ge 1 ]; then
  readarray -d '' tmp_array < \
      <(find "${argv[@]}"  -print0)
      
  argv=( "${tmp_array[@]}" )
fi

  


if [ "$do_operation" == "ffprobe_json" ]; then
  echo "["
fi

if [ "$save_output_files" -ge 1 ]; then
  rm -f "$file_out_csv"
  rm -f "$file_out_raw"
fi

for file in "${argv[@]}" ; do
  if [ ! -f "$file" ]; then
    continue
  fi
  
  ext="`extension_lower "$file" `"
  
  case "$ext" in
  mp3)
    test_1_file "$file"
    ;;

  mp3|mp4|avi|m4a|opus|webm|wav|flac|alac|aiff)
    pass
    ;;
    
  *)
    pass
    #echo "ignoring $file"
    ;;
  esac
  
done

if [ "$do_operation" == "ffprobe_json" ]; then
  echo "{ }]"
fi


exit 0



TODO: recursive
rawcat : break info


#define ID3V2_ID_STRING                      "ID3"

#define LYRICS3_BEGIN_SIGNATURE      "LYRICSBEGIN"
#define LYRICS3V1_END_SIGNATURE        "LYRICSEND"
#define LYRICS3V2_END_SIGNATURE        "LYRICS200"
#define APETAGEX_SIGNATURE              "APETAGEX"
#define WAVE_RIFF_DATA_ID                   "data"

#define VBRI_TAG_START_OFFSET                   36
#define VBRI_TAG_ID_STRING                  "VBRI"
#define LAME_TAG_ID_STRING                  "Info"
#define XING_TAG_ID_STRING                  "Xing"



