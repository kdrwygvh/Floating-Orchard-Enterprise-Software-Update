#!/bin/zsh
#shellcheck shell=bash

# Title         :macOS Download Upgrade Reinstall Erase.sh
# Description   :Performs an upgrade, reinstall, or erase of macOS based on Jamf variables
# Author        :John Hutchison
# Date          :2022-08-08
# Contact       :john@randm.ltd, john.hutchison@floatingorchard.com
# Version       :1.3.4.2
# Notes         : Updated to support disk spce checking on HFS+ filesystems
#                 Updated to use custom installer paths
#                 Updated to do variable free space checks based target upgrade OS
#                 Updated to allow for download of macOS in the absence of an interactive login
#                 Updated to account for multiple copies of macOS Install.app on disk
#                 Added Do Not Disturb checks
#                 Added support for upgrading from Journaled HFS+ Volumes
#                 Replaced all jamfHelper Notifications with Shui function
#                 Will accept the preferred or newer version of the installer

# The Clear BSD License
#
# Copyright (c) [2021] [John Hutchison of Russell & Manifold ltd.]
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted (subject to the limitations in the disclaimer
# below) provided that the following conditions are met:
#
#      * Redistributions of source code must retain the above copyright notice,
#      this list of conditions and the following disclaimer.
#
#      * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#
#      * Neither the name of the copyright holder nor the names of its
#      contributors may be used to endorse or promote products derived from this
#      software without specific prior written permission.
#
# NO EXPRESS OR IMPLIED LICENSES TO ANY PARTY'S PATENT RIGHTS ARE GRANTED BY
# THIS LICENSE. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
# CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR Ax`
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# WARNING: If you regularly package macOS Installers using Packages, Composer etc... you
# probably do not want to use this tool on yourself. It will delete any outdated installers
# it finds in favor of the version specified during script execution. Use responsibly.

# Notes on Bundle Versions of the macOS Installer App
# Additional info for macOS Installers available at
# https://mrmacintosh.com/macos-big-sur-full-installer-database-download-directly-from-apple/
# https://mrmacintosh.com/macos-12-monterey-full-installer-database-download-directly-from-apple/

# Jamf Variable Label names

# $4 -eq Installer Name (e.g. Install macOS Big Sur)
# $5 -eq Preferred Installer Version (e.g. 16.5.01)
# $6 -eq Installer Download Version from Apple CDN (e.g. 11.3)
# $7 -eq Installer Download Jamf Event (10.14 and Prior)
# $8 -eq Install Action (downloadonly, upgrade, reinstall, erase, eacas)
# $9 -eq Suppress all Notifications (true/false)
# $10 -eq Custom Logo Path for Notifications
# $11 -eq Perform Network Link Evaluation (true/false)

# Certain security products, network proxies, or filters may prevent some or all of the
# network link tests from passing while allowing software updates in general. Test.

logDateHeader(){
  echo "$(/bin/date) - $*"
}

## BEGIN SHUI FUNCTION ##
function shui {
[ -n "${-//[^x]/}" ] && { local xTrace=1; set +x; } 2>/dev/null
local version="20220704"
: <<-EOL
shui.min - a zsh/bash function to easily add Applescript user interaction to your script (https://github.com/brunerd/shui)
Copyright (c) 2020 Joel Bruner
MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
EOL
#these GLOBAL vars are reset each time shui runs
unset lastButton lastText lastChoice lastGaveUp lastCancel lastError lastResult lastPID
[ "${shui_silentMode}" = "Y" ] || [ "${silentMode}" = "Y" ] && return; [ "$(cut -d. -f1 <<< $(sw_vers -productVersion))" -eq 10 ] && [ "$(cut -d. -f2 <<< $(sw_vers -productVersion))" -le 8 ] && echo "shui requires macOS 10.9 and above" >&2 && return 1; local defaultIcon="${shui_defaultIcon}";[ -n "${shui_defaultTitle}" ] && local defaultTitle="$(echo -e "${shui_defaultTitle}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";[ -n "${shui_defaultOption}" ] && local defaultOption="$(echo -e "${shui_defaultOption}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')"; local timeoutSecondsAppleScript=${shui_timeoutDefault:-"133200"}; local defaultApplication="${shui_defaultApplication}"; local defaultColorRGB="${shui_defaultColor:-65535,65535,65535}"; local timeoutSecondsAppleScript=${timeoutDefault:-"133200"};local consoleUserID="$(stat -f %u /dev/console)";local consoleUser="$(stat -f %Su /dev/console)"; if [ -n "$ZSH_VERSION" ]; then set -y; elif [ -n "$BASH_VERSION" ]; then local array_offset="1"; unset OPTIND OPTARG; fi;local NL=$'\n';local asuserPrefix="launchctl asuser ${consoleUserID} sudo -u ${consoleUser}";if [ "$(cut -d. -f1 <<< $(sw_vers -productVersion))" -eq 10 ] && [ "$(cut -d. -f2 <<< $(sw_vers -productVersion))" -le 10 ]; then if [ "${USER}" = "${consoleUser}" ]; then unset asuserPrefix; elif [ "${USER}" != "${consoleUser}" ] && [ "$UID" -ne 0 ] && [ "${SUDO_USER}" != "${consoleUser}" ]; then echo "Script user ($USER) ≠ console user ($consoleUser), please run as root on 10.10 and 10.9" >&2;return 1;fi;fi;local APPLESCRIPT
read -r -d '' helpText <<'EOT'
shui (20220704) - add Applescript user interaction to your shell script (https://github.com/brunerd/shui)\n\nUsage:\nshui [<UI Type>] -p "<prompt text>" \n\nUI Types:\nalert: alert with icon of the calling appication (use -a), prompt (-p) is bold, message text (-P) is smaller, can set level (-L) to critical\napplication: presents list of Launch Services registered applicatins can specify -m for multiple\nbutton (default): button based reply, use -b to change button names (max 3), defaults to "Cancel,OK" like Applescript does\ncolor: no options, presents color picker and returns "R,G,B" with individual values (0-65535)\nfile: pick one file or multiple (-m), -d for default folder, -P to specify preferred file extensions or UTIs, -h hidden items, -s show bundle contents\nfolder: pick one file or multiple (-m), -d for default folder, -P to specify preferred file extensions, -h hidden items, -s show bundle contents\nlist: pick one or mutiple (-m) items from a list of choices, use -D for custom delimiter (comma default)\ntext: like button but with a single line text entry box, set pre-filled text with -P, hidden text with -h\nurl: returns a URL, default is file servers, use -S to set the kind of server to look for, valid value listed below\n\nRequired:\n-p "prompt text"\talert/button/file/folder/list: the text prompt presented to the user, required for all type (except color)\n\nOptions (begins with UI type(s) which apply or "all"):\n\n-a "<application>"\tall (except filename): specify the application that will present the Applescript dialog, alert will have app icon and block app\n\n-b "<button>;...;..."\tbutton: max 3 button names, comma or semi-colon delimited (if commas AND semi-colons are present, semis "win") \n\t\t\t\t\t\tif no buttons specified it defaults to the standard Applescript "Cancel,OK"\n-b "<OK>,[<Cancel>]"\tlist: max 2 button names, comma delimited, first is the OK button name, second is Cancel button name (optional)\n\n-B "n"\t\t\tall: beep n number of times\n\n-c "name/number"\tbutton: specify the cancel button by name or number (use with alert and buttons named "Cancel")\n\n-d "name/number"\tbutton: default button name or number (0 will suppress Applescript OK button default if -b not specified)\n-d "<Folder Path>"\tfile/folder: default location (Unix Path), using ~ will resolve to the console user's home folder\n\n-D "<delimiter>"\tlist: Delimiter for -l list items, can specify literal character like $'\\n' or use these two named shortcuts "LF" "IFS"\n\n-e \t\t\tlist: allow empty selection\n\n-g "seconds"\t\talert/button: give-up timeout in seconds (dismisses windows and moves on)\n\n-h\t\t\ttext: hidden text entry (dots)\n-h\t\t\tfile/folder: show hidden files in picker\n\n-i "<path>"\t\tbutton: path to icon file or application bundle (Icon^M first, then Info.plist)\n\n-l "item,item,..."\tlist: items for list, comma delimited is default unless newline is detected (change delimiter with -D)\n\n-L "<level>"\t\talert: default is ‌"informational"/"‌warning" (same), "critical" adds a caution sign over the calling app (-a) icon\n\n-m\t\t\tapplication/file/folder/list: allow multiple selections\n\n-n\t\t\talert/button: non-Blocking window, spawns to a background and moves on, response is not captured, one button maximum\n \t\t\tNote: If this is NOT the last alert window it is advisable to use a giveup (-g) value, additional dialogs will occlude previous ones (use -X to clear)\n\n-N\t\t\talert/button: same as (-n) non-blocking window except button 1 is default\n\n-o\t\t\tall: output shell arguments, Applescript code and raw Results and Errors\n\n-P "message text"\talert: "parenthetical" message text below the bold prompt text\n-P "<R>,<G>,<B>"\tcolor: pre-chosen RGB color values 0-65535\n-P "filename"\t\tfilename: pre-filled file name (default folder set with -d)\n-P "extension,UTI,..."\tfile: "preferred" file extensions/UTIs available to choose in picker\n-P "item,item..."\tlist: pre-chosen items, default delimiter is comma unless a newline is present or can be set with -D\n-P "pre-fill text"\ttext: pre-filled text (may be hidden with -h)\n\n-S "<Service>"\t\turl: look for specific services, useful values are: "file" (default) and "web" \n\t\t\tLess useful but still valid values are: "ftp", "media", "telnet", "news", "remote" (applications), and "directory" (services)\n\n-s\t\t\tfile/folder: show package/bundle contents (as a folder basically)\n\n-t "Title text"\t\tbutton/list/text: window title\n\n-v\t\t\tall: output results in format suitable for initializing shell variables\n-V\t\t\tall: output results in format suitable for initializing shell variables plus Applescript and raw Result/Error output from osascript (-o)\n\n-X\t\t\talert/button: kill ALL osascript and "System Events" processes, like orphaned non-Blocking (background) windows. Use with CAUTION!\n-x\t\t\talert/button: kill only child osascript processes belonging to the running script (embedded usage only)\n\nshui sets these GLOBAL variables within the script's running context (use -v to output these if shui is standalone/non-embedded):\n\tlastButton - value of button from button, text, and list replies\n\tlastText   - Text string from text reply\n\tlastChoice - File or Folder Unix path from files/filename/folders\n\tlastGaveUp - true or false, button and text reply types only, when a give up (-g) value is specified\n\tlastCancel - true or false, since Cancel produces an error and no result this helps determine if clicked\n\tlastResult - full Result output (stdout) from osascript that is parsed into the above values\n\tlastError  - full Error (stderr) output from osascript\n\tlastPID    - the child PID of a non-blocking (-n) alert or button (excluding -a invoked)\n\nshui will use these GLOBAL variables set in your script or exported in your running shell\n\tshui_defaultIcon - icon path for button UIs\n\tshui_defaultTitle - title string for button, text, and list UIs\n\tshui_defaultOption - button by name or number or file/folder by path\n\tshui_defaultColor - default color (picker) UI "<R>,<G>,<B>" 0-65535
EOT
if [ -z "${1}" ]; then echo -e "No arguments given!\nFor usage: shui help\nFor examples: shui demo" >&2; return 1;elif [ "${1}" = "help" ]; then echo "${helpText}" >&2;return 0;elif [ "${1}" = "version" ]; then echo "${version}"; return 0;elif [ "$(cut -c1-1 <<< ${1})" = "-" ]; then local uiType="button";else local uiType="$(tr "[[:upper:]]" "[[:lower:]]" <<< "${1}")";shift 1;fi;local option;while getopts ":B:L:t:g:P:p:i:b:c:D:S:d:l:a:nehmNsovVXx" option; do case "${option}" in 'a')local applicationNameArg="${OPTARG}";;'b')local buttonListArgs="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";;'B')local beep_AS="beep ${OPTARG}";;'c')local cancelButton="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";; 'd')local defaultOption="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";;'D')local listDelimiter="${OPTARG}";;'e')local withEmpty_AS="with empty selection allowed";;'g')local giveupSeconds="${OPTARG}";;'h')local option_H_flag="1";;'i')local iconArgument="${OPTARG}";;'L')local alertLevel_AS="as ${OPTARG}";;'l')local listItems="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";;'m')local withMultiple_AS="with multiple selections allowed";;'n')local nonBlockingFlag="1";;'N')local nonBlockingFlag="1";local defaultOption="1";;'o')local outputFlag="1";;'p')local promptString="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')"; local withPrompt_AS="with prompt \"${promptString}\"";;'P')local preFillString="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";;'S')local serviceArgument="${OPTARG}";;'s')local showingPackage_AS="with showing package contents";;'t')local titleString="$(echo -e "${OPTARG}" | sed -e 's/\\/\\\\/g' -e 's/\"/\\\"/g')";;'v')local variableFlag="1";;'V')local variableFlag="1";local outputFlag="1";local variableFlagPlus="1";;'X')[ -z "${killChildProcsOnly}" ] && local killAllProcs="1";;'x')[ -z "${killAllProcs}" ] && local killChildProcsOnly="1";;esac;done;if [ -z "${promptString}" ] && [ "${uiType}" != "color" ] && [ "${uiType}" != "url" ]; then echo "Please provide prompt text in the form of: shui <UI Type> -p \"<prompt text>\"\nFor usage: shui help\nFor examples: shui demo" >&2;return;fi;if [ -z "${applicationNameArg}" ] && [ -n "${defaultApplication}" ]; then local applicationNameArg="${defaultApplication}"; fi; if [ -z "${iconArgument}" ] && [ -n "${defaultIcon}" ]; then local iconArgument="${defaultIcon}"; fi;if [ "${uiType}" = "color" ] && [ -z "$applicationNameArg" ]; then local applicationNameArg="System Events"; fi;if [ -n "${applicationNameArg}" ]; then local tellApp_AS="tell application \"${applicationNameArg}\"";local endTell_AS="end tell";fi;[ -z "${titleString}" ] && [ -n "${defaultTitle}" ] && local titleString="${defaultTitle}";case "${uiType}" in "list") local listItems_AS preChosenList_AS listArray preChosenArray button_OK button_cancel;if [ -z "${listItems}" ]; then echo -e "No data for list!\nSpecify list data with: -l \"<data>\"\nDefault delimiter comma (,) can be changed with -D \"<char>\"";return 1;fi;[ -n "$titleString" ] && local title_AS="with title \"$titleString\"";if [ -n "${buttonListArgs}" ]; then if [ "$(grep -c $'\n' <<< "${buttonListArgs}")" -ge 2 ]; then local button_OK="$(sed -n 1p <<< "${buttonListArgs}")";local button_cancel="$(sed -n 2p <<< "${buttonListArgs}")";else [ "$(grep -c $';' <<< "${buttonListArgs}")" -ge 1 ] && local buttonDelimiter=';' || local buttonDelimiter=',';local button_OK="$(cut -d "${buttonDelimiter}" -f1 <<< "${buttonListArgs}")";local button_cancel="$(cut -d "${buttonDelimiter}" -f2 <<< "${buttonListArgs}")";[ "${button_cancel}" = "${button_OK}" ] && local button_cancel="";fi;fi;if [ "${listDelimiter}" = "IFS" ]; then IFS=$' \n\t' listArray=( ${listItems} ); elif [ "${listDelimiter}" = "LF" ]; then IFS=$'\n' listArray=( ${listItems} ); elif [ -n "${listDelimiter}" ]; then IFS=${listDelimiter} listArray=( ${listItems} );else if [ "$(grep -c $'\n' <<< "${listItems}")" -ge 2 ]; then IFS=$'\n' listArray=( ${listItems} );else IFS=, listArray=( ${listItems} );fi;fi;for (( j=$(( 1 - ${array_offset:-0} )); j <= $(( ${#listArray[@]} - ${array_offset:-0} )); j++ )); do [ -z "$listItems_AS" ] && listItems_AS+="\"${listArray[$j]}\"" || listItems_AS+=", \"${listArray[$j]}\"";done;if [ -n "$preFillString" ]; then if [ "${listDelimiter}" = "IFS" ]; then IFS=$' \n\t' preChosenArray=( ${preFillString} );elif [ "${listDelimiter}" = "LF" ]; then IFS=$'\n' preChosenArray=( ${preFillString} ); elif [ -n "${listDelimiter}" ]; then IFS=${listDelimiter} preChosenArray=( ${preFillString} ); else if [ "$(grep -c $'\n' <<< "${preFillString}")" -ge 2 ]; then IFS=$'\n' preChosenArray=( ${preFillString} );else IFS=, preChosenArray=( ${preFillString} );fi;fi;for (( j=$(( 1 - ${array_offset:-0} )); j <= $(( ${#preChosenArray[@]} - ${array_offset:-0} )); j++ )); do [ -z "${preChosenList_AS}" ] && preChosenList_AS+="\"${preChosenArray[$j]}\"" || preChosenList_AS+=", \"${preChosenArray[$j]}\"";[ -z "${withMultiple_AS}" ] && break;done;local defaultItems_AS="default items {${preChosenList_AS}}";fi
read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}set dialogAnswer to choose from list {${listItems_AS}} ${withMultiple_AS} ${title_AS} ${withPrompt_AS} ${defaultItems_AS} ${withEmpty_AS} OK button name {"${button_OK:-OK}"} cancel button name {"${button_cancel:-Cancel}"}${NL}if class of dialogAnswer is boolean then${NL}error number -128${NL}end if${NL}if (count of dialogAnswer) is greater than 1 then${NL}set dialogAnswers to ""${NL}repeat with choice from 1 to count of dialogAnswer${NL}set theCurrentItem to item choice of dialogAnswer${NL}set dialogAnswers to dialogAnswers & theCurrentItem & "\n"${NL}end repeat${NL}else${NL}return dialogAnswer as string${NL}end if${NL}end timeout${NL}${endTell_AS}
EOF
;;"file"*|"folder")[ "${option_H_flag:=0}" -eq 1 ] && local withInvisibles_AS="with invisibles";if [ -d "${defaultOption}" ]; then local folderPath="${defaultOption}";elif [ "${defaultOption:0:1}" = '~' ]; then local homeFolder="$(dscl . -read /Users/$consoleUser NFSHomeDirectory | awk -F ": " '{print $NF}')"; local folderPath="${homeFolder}${defaultOption:1}";elif [ -n "${ZSH_VERSION}" ]; then local folderPath="$(dirname "${ZSH_ARGZERO:=${${funcfiletrace[-1]}[(ws/:/)1]}}")";elif [ -e "${0}" ]; then local folderPath="$(dirname "$0")";else local folderPath="$(pwd)";fi;case "${uiType}" in "filename")if [ -n "${preFillString}" ]; then local defaultNameString="default name \"$preFillString\"";fi;
read -r -d '' APPLESCRIPT <<-EOF
${beep_AS}${NL}get POSIX path of (choose file name ${defaultNameString} ${withPrompt_AS} default location POSIX file "$folderPath")
EOF
;;"file"|"folder")if [ -n "${preFillString}" ]; then local choice;local fileTypeList;IFS=,;for choice in $preFillString; do [ -z "$fileTypeList" ] && fileTypeList=\"$choice\" || fileTypeList+=,\ \"$choice\";done;IFS=$' \n\t';local ofType_AS="of type {$fileTypeList}";fi;
read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}set dialogAnswer to choose ${uiType} ${withInvisibles_AS} ${withPrompt_AS} ${ofType_AS} ${withMultiple_AS} default location POSIX file "${folderPath}" ${showingPackage_AS}${NL}if class of dialogAnswer is list then${NL}set dialogAnswers to ""${NL}repeat with thisAlias from 1 to count of dialogAnswer${NL}set dialogAnswers to dialogAnswers & POSIX path of item thisAlias of dialogAnswer & "\n"${NL}end repeat${NL}else if class of dialogAnswer is alias then${NL}set dialogAnswer to POSIX path of dialogAnswer${NL}end if${NL}end timeout${NL}${endTell_AS}
EOF
;;esac;;"application"*)read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}set dialogAnswer to choose application ${title_AS} ${withPrompt_AS} ${withMultiple_AS} as alias${NL}if class of dialogAnswer is list then${NL}set dialogAnswers to ""${NL}repeat with thisAlias from 1 to count of dialogAnswer${NL}set dialogAnswers to dialogAnswers & POSIX path of item thisAlias of dialogAnswer & "\n"${NL}end repeat${NL}else if class of dialogAnswer is alias then${NL}set dialogAnswer to POSIX path of dialogAnswer${NL}end if${NL}end timeout${NL}${endTell_AS}
EOF
;;"color")if [ -n "${preFillString}" ] ; then local R="$(cut -d, -f1 <<< "${preFillString}")";local G="$(cut -d, -f2 <<< "${preFillString}")";local B="$(cut -d, -f3 <<< "${preFillString}")";if [ "${R}" -ge 0 ] && [ "${R}" -le 65535 ] && [ "${G}" -ge 0 ] && [ "${G}" -le 65535 ] && [ "${B}" -ge 0 ] && [ "${B}" -le 65535 ]; then defaultColor_AS="default color {${preFillString}}";fi;elif [ -n "${defaultColorRGB}" ]; then defaultColor_AS="default color {${defaultColorRGB}}";fi;
read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}set theColor to choose color ${defaultColor_AS}${NL}end timeout${NL}${endTell_AS}
EOF
;;"url")if [ -n "${serviceArgument}" ]; then case "${serviceArgument}" in "file") local servicename_AS="File servers";;"web") local servicename_AS="Web servers";;"ftp") local servicename_AS="FTP Servers";;"media") local servicename_AS="Media servers";;"telnet") local servicename_AS="Telnet hosts";;"news") local servicename_AS="News servers";;"remote") local servicename_AS="Remote applications";;"directory") local servicename_AS="Directory services";;esac;[ -n "${servicename_AS}" ] && showingService_AS="showing ${servicename_AS}";fi
read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}choose URL ${showingService_AS}${NL}end timeout${NL}${endTell_AS}
EOF
;;"alert"|"button"|"text"|*)case "${uiType}" in "alert")local windowType="alert";[ -n "${preFillString}" ] && local message_AS="message \"${preFillString}\"";;"button"|"text")local windowType="dialog";unset alertLevel_AS;[ -n "$titleString" ] && local title_AS="with title \"$titleString\"";;*)echo -e "Unknown UI Type: \"${uiType}\"\nFor usage: shui help\nFor examples: shui demo" >&2;return 1;;esac;[ -z "${nonBlockingFlag}" ] && local buttonCountLimit=3 || local buttonCountLimit=1;if [ -z "$buttonListArgs" ] && [ -n "${nonBlockingFlag}" ]; then local buttonListArgs="OK";fi;if [ "$(grep -c $'\n' <<< "$buttonListArgs")" -ge 2 ]; then IFS=$'\n';elif [ "$(grep -c ';' <<< "$buttonListArgs")" -ge 1 ]; then IFS=$';';else IFS=,;fi;local button buttonListItems buttonCount;for button in ${buttonListArgs}; do [ -z "$button" ] && continue;button="$(sed "s/^[ ]*//;s/[ ]*$//" <<< "$button" )";[ -z "$buttonListItems" ] && buttonListItems=\"${button}\" || buttonListItems+=,\ \"${button}\";let $((buttonCount++));[ "${buttonCount:=1}" -ge "${buttonCountLimit}" ] && break;done;IFS=$' \n\t';[ -n "${buttonListItems}" ] && buttons_AS="buttons {${buttonListItems}}";if [ -n "${defaultOption}" ] && [ "${defaultOption}" = "$(bc 2>/dev/null <<< "${defaultOption}")" ]; then if [ "${defaultOption}" -ge 1 ] && [ "${defaultOption}" -le "${buttonCount}" ]; then local defaultButton_AS="default button ${defaultOption}"; fi;elif [ -n "${defaultOption}" ] && [ -n "$(grep -w "${defaultOption}" <<< "${buttonListItems}")" ]; then local defaultButton_AS="default button \"${defaultOption}\"";fi;if [ -n "${cancelButton}" ] && [ "${cancelButton}" = "$(bc 2>/dev/null <<< "${cancelButton}")" ]; then if [ "${cancelButton}" -ge 1 ] && [ "${cancelButton}" -le "${buttonCount}" ]; then local cancelButton_AS="cancel button ${cancelButton}";fi;elif [ -n "${cancelButton}" ] && [ -n "$(grep -w "${cancelButton}" <<< "${buttonListArgs}")" ]; then local cancelButton_AS="cancel button \"${cancelButton}\"";fi;if [ -f "${iconArgument}" ] && [ "${uiType}" != "alert" ]; then local withIcon_AS="with icon file (POSIX file \"${iconArgument}\")";elif [ ! -f "${iconArgument}" ] && [ "${uiType}" != "alert" ]; then case "${iconArgument}" in "stop"|"0")if [ -z "${applicationNameArg}" ] || [ "${applicationNameArg}" = "System Events" ]; then local alertIconUnixPath="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"; else local alertIconName="stop";fi;;"caution"|"2")if [ -z "${applicationNameArg}" ] || [ "${applicationNameArg}" = "System Events" ]; then local alertIconUnixPath="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"; [ ! -f "${alertIconUnixPath}" ] && alertIconUnixPath="/System/Library/CoreServices/Problem Reporter.app/Contents/Resources/ProblemReporter.icns";else local alertIconName="caution";fi;;"note"|"1")if [ -z "${applicationNameArg}" ] || [ "${applicationNameArg}" = "System Events" ]; then local alertIconUnixPath="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns";else local alertIconName="note";fi;;*)if [ -f "${iconArgument}/Icon"$'\r' ]; then local tempIcon="/tmp/shui_icon-${RANDOM}.icns"; local resourceHexString="$(xattr -p com.apple.ResourceFork "${iconArgument}/Icon"$'\r')";[ -n "${resourceHexString}" ] && xxd -r -p - <<< "${resourceHexString:780}" > "${tempIcon}";if [ -s "${tempIcon}" ] && [ -z "$(grep ": data" <<< "$(file "${tempIcon}")")" ]; then local alertIconUnixPath="${tempIcon}"; fi;fi;if [ -f "${iconArgument}"/Contents/Info.plist ] && [ -z "${alertIconUnixPath}" ]; then local bundleIconFileName="$(defaults read "${iconArgument}"/Contents/Info.plist CFBundleIconFile 2>/dev/null)"; [ -z "${bundleIconFileName}" ] && bundleIconFileName="$(defaults read "${iconArgument}"/Contents/Info.plist CFBundleIconName 2>/dev/null)"; [ "${bundleIconFileName}" = "${bundleIconFileName/.icns/}" ] && bundleIconFileName="${bundleIconFileName}".icns;local bundleIconPath="${iconArgument}"/Contents/Resources/"${bundleIconFileName}";if [ -f "${bundleIconPath}" ]; then local alertIconUnixPath="${bundleIconPath}";else local alertIconUnixPath="${defaultIcon}";fi;fi;;esac;if [ -f "${alertIconUnixPath}" ]; then local withIcon_AS="with icon file (POSIX file \"${alertIconUnixPath}\")";elif [ -n "${alertIconName}" ]; then local withIcon_AS="with icon ${alertIconName}";fi;fi;[ "${option_H_flag:=0}" -eq 1 ] && local withHiddenAnswer_AS="with hidden answer";if [ -n "${nonBlockingFlag}" ] && [ "${uiType}" = "text" ]; then unset nonBlockingFlag;fi;if [ "${uiType}" = "text" ]; then local defaultAnswer_AS="default answer \"$preFillString\"";fi;if [ -z "${iconArgument}" ] && [ -n "${defaultIcon}" ]; then local iconArgument="${defaultIcon}";fi;if [ "${iconArgument:0:1}" = '~' ]; then local homeFolder="$(dscl . -read /Users/$consoleUser NFSHomeDirectory | awk -F ": " '{print $NF}')"; local iconArgument="${homeFolder}${iconArgument:1}";fi;[ -n "${giveupSeconds}" ] && local giveup_AS="giving up after \"$giveupSeconds\"";if [ -n "${nonBlockingFlag}" ]; then
read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}set dialogAnswer to display ${windowType} "${promptString}" ${alertLevel_AS} ${message_AS} ${title_AS} ${withIcon_AS} ${buttons_AS} ${giveup_AS} ${defaultButton_AS} ${cancelButton_AS}${NL}end timeout${NL}${endTell_AS}
EOF
else read -r -d '' APPLESCRIPT <<-EOF
${tellApp_AS}${NL}activate${NL}${beep_AS}${NL}with timeout of $timeoutSecondsAppleScript seconds${NL}set dialogAnswer to display ${windowType} "${promptString}" ${alertLevel_AS} ${message_AS} ${defaultAnswer_AS} ${withHiddenAnswer_AS} ${title_AS} ${withIcon_AS} ${buttons_AS} ${giveup_AS} ${defaultButton_AS} ${cancelButton_AS}${NL}end timeout${NL}${endTell_AS}
EOF
fi;;esac;if [ -n "$outputFlag" ]; then local a invocationQuoted; if [ -n "$ZSH_VERSION" ]; then for ((a=1; a <= ${#argv[@]}; a++ )); do [ "${argv[$a]:0:1}" = '-' ] && invocationQuoted+="${argv[$a]} " || invocationQuoted+="'${argv[$a]}' "; done; elif [ -n "$BASH_VERSION" ]; then if [ "${BASH_ARGC:-0}" -eq 1 ]; then local invocationQuoted="$@"; else for ((a=$((${BASH_ARGC:-0}-2)); a >= 0; a-- )); do [ "${BASH_ARGV[$a]:0:1}" = '-' ] && invocationQuoted+="${BASH_ARGV[$a]} " || invocationQuoted+="'${BASH_ARGV[$a]}' ";done;fi;fi;echo -e "Arguments:\n${uiType} ${invocationQuoted}\n" >&2;fi;[ -n "$outputFlag" ] && (echo "Applescript:" >&2; cat <<< "$APPLESCRIPT" | tr -s ' ' | sed '/^$/d' >&2; echo >&2);if [ -n "${killAllProcs}" ]; then local sysEventsPID osascriptPID;for sysEventsPID in $(pgrep System\ Events); do eval ${asuserPrefix} kill -9 "${sysEventsPID}";done;for osascriptPID in $(pgrep osascript); do eval ${asuserPrefix} kill -9 "${osascriptPID}";done;fi;if [ -n "${killChildProcsOnly}" ]; then local sysEventsPID osascriptPID childPID; local childPIDs="$(pgrep -P $$)"; for childPID in $(pgrep -P $$); do local grandChildPID="$(pgrep -P $childPID)";local grandChildPIDString="$(ps ${grandChildPID} | tail -n +2)";if grep -q "osascript$" <<< "${grandChildPIDString}"; then if grep -q "sudo$" <<< "$(pgrep -laP $childPID)"; then local childPIDToKill="$(pgrep -P $grandChildPID)"; else local childPIDToKill="${grandChildPID}"; fi;fi;[ -n "${childPIDToKill}" ] && eval ${asuserPrefix} kill -9 "${childPIDToKill}";done;fi;if [ -z "${nonBlockingFlag}" ]; then local tempStdErrFile="/tmp/shuiError-$$-${RANDOM}.txt";lastResult="$(eval ${asuserPrefix} /usr/bin/osascript 2>${tempStdErrFile} <<< "$APPLESCRIPT")";lastError="$(< "${tempStdErrFile}")";rm "${tempStdErrFile}";[ $(( $(wc -l <<< "${lastError}") )) -gt 1 ] && local lastError_escaped="$(sed -e 's/\\/\\\\/g' -e :a -e N -e '$!ba' -e 's/\n/\\n/g' <<< "${lastError}")" || local lastError_escaped="$(sed -e 's/\\/\\\\/g' <<< "${lastError}")";lastError_escaped="$(sed -e $'s/\r/\\\\r/g' -e $'s/\t/\\\\t/g' -e $'s/\b/\\\\b/g' -e $'s/\f/\\\\f/g' -e $'s/\v/\\\\v/g' -e $'s/\'/\\\\\'/g' <<< "${lastError_escaped}")";else { ( eval ${asuserPrefix} /usr/bin/osascript &>/dev/null <<< "$APPLESCRIPT"; [ -e "${tempIcon}" ] && rm -f "${tempIcon}" ) & };local childPID=$!;sleep .2; local grandChildPID="$(pgrep -P ${childPID})";if [ -n "${grandChildPID}" ] && [ -z "${tellApp_AS}" ]; then if grep -q "sudo$" <<< "$(pgrep -laP $childPID)"; then lastPID="$(pgrep -P $grandChildPID)"; else lastPID="${grandChildPID}"; fi;fi;fi;if [ -n "${lastResult}" ]; then [ $(( $(wc -l <<< "${lastResult}") )) -gt 1 ] && local lastResult_escaped="$(sed -e 's/\\/\\\\/g' -e :a -e N -e '$!ba' -e 's/\n/\\n/g' <<< "${lastResult}")" || local lastResult_escaped="$(sed -e 's/\\/\\\\/g' <<< "${lastResult}")";lastResult_escaped="$(sed -e $'s/\r/\\\\r/g' -e $'s/\t/\\\\t/g' -e $'s/\b/\\\\b/g' -e $'s/\f/\\\\f/g' -e $'s/\v/\\\\v/g' -e $'s/\'/\\\\\'/g' <<< "${lastResult_escaped}")";local lastResultFragment_escaped="${lastResult_escaped}";case "${uiType}" in "alert"|"button"|"text") if [ -n "${giveup_AS}" ]; then if grep -q "gave up:true$" <<< "${lastResultFragment_escaped}"; then lastGaveUp="true";else lastGaveUp="false";fi;lastResultFragment_escaped=$(sed -e 's/, gave up:true$//' -e 's/, gave up:false$//' <<< "${lastResultFragment_escaped}");fi;local lastButton_escaped="$(awk -F '^button returned:|, text returned:' '{print $2}' <<< "${lastResultFragment_escaped}")";lastCancel="false";eval lastButton=\$\'"${lastButton_escaped}"\';lastResultFragment_escaped="$(sed -e 's/^button returned:'"${lastButton_escaped//\\/\\\\}"'//' <<< "${lastResultFragment_escaped}")";if grep -q "^, text returned:" <<< "${lastResultFragment_escaped}"; then local lastText_escaped="$(sed -e 's/^, text returned://' <<< "${lastResultFragment_escaped}")";eval lastText=\$\'"${lastText_escaped}"\';fi;;"file"*|"folder"|"application"|"color"|"url"|*) lastChoice="${lastResult}";[ $(( $(wc -l <<< "${lastChoice}") )) -gt 1 ] && local lastChoice_escaped="$(sed -e 's/\\/\\\\/g' -e :a -e N -e '$!ba' -e 's/\n/\\n/g' <<< "${lastChoice}")" || local lastChoice_escaped="$(sed -e 's/\\/\\\\/g' <<< "${lastChoice}")";lastChoice_escaped="$(sed -e $'s/\r/\\\\r/g' -e $'s/\t/\\\\t/g' -e $'s/\b/\\\\b/g' -e $'s/\f/\\\\f/g' -e $'s/\v/\\\\v/g' -e $'s/\'/\\\\\'/g' <<< "${lastChoice_escaped}")";lastCancel="false";;esac;elif [ "${uiType}" = "url" ] && [ -z "${lastError}" ]; then lastCancel="false";elif [ -z "${nonBlockingFlag}" ]; then lastCancel="true";fi;[ -e "${tempIcon}" ] && [ -z "${nonBlockingFlag}" ] && rm -f "${tempIcon}";if [ -n "${outputFlag}" ] || [ -n "${variableFlagPlus}" ]; then printf "Result:\n%s\n\n" "${lastResult}" >&2;printf "Error:\n%s\n\n" "${lastError}" >&2;fi;if [ -n "${variableFlag}" ]; then /bin/echo "lastButton=\$'${lastButton_escaped}'";/bin/echo "lastText=\$'${lastText_escaped}'";/bin/echo "lastChoice=\$'${lastChoice_escaped}'";/bin/echo "lastGaveUp='${lastGaveUp}'";/bin/echo "lastCancel='${lastCancel}'";/bin/echo "lastResult=\$'${lastResult_escaped}'";/bin/echo "lastError=\$'${lastError_escaped}'";/bin/echo "lastPID='${lastPID}'";fi;[ -n "${lastError}" ] || [ "${lastCancel}" = "true" ] && return 1; [ "${xTrace:-0}" = 1 ] && { set -x; } 2>/dev/null
}
## END SHUI FUNCTION ##

getJsonValue() {
  # $1: JSON string OR file path to parse (tested to work with up to 1GB string and 2GB file).
  # $2: JSON key path to look up (using dot or bracket notation).
  printf '%s' "$1" | /usr/bin/osascript -l 'JavaScript' \
    -e 'let json = $.NSString.alloc.initWithDataEncoding($.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile, $.NSUTF8StringEncoding)' \
    -e 'if ($.NSFileManager.defaultManager.fileExistsAtPath(json)) json = $.NSString.stringWithContentsOfFileEncodingError(json, $.NSUTF8StringEncoding, ObjC.wrap())' \
    -e "JSON.parse(json.js)$([ -n "${2%%[.[]*}" ] && echo '.')$2"
}

# Installer Variables
installerName="$4" # Required
macOSPreferredBundleVersion="$5" # Required
macOSDownloadVersion="$6" # Required
macOSInstallAppJamfEvent="$7" # Optional
installAction="$8" # Required
runHeadless="$9" # Required
logoPath=${10} # Optional
networkLinkEvaluation=${11} # Required true/false
localAdminPasswordForHeadlessInstalls=''

# Check required variables

if [[ "$installerName" = "" ]]; then echo "Installer Name was not set, bailing"; exit 2; fi
if [[ "$macOSDownloadVersion" = "" ]]; then echo "Installer Download Version was not set, bailing"; exit 2; fi
if [[ "$installAction" = "" ]]; then echo "Install Action was not set, bailing"; exit 2; fi
if [[ "$runHeadless" = "" ]]; then echo "Headless preference was not set, bailing"; exit 2; fi
if [[ "$networkLinkEvaluation" = "" ]]; then echo "Network Link Evaluation preference was not set, bailing"; exit 2; fi

# Validate logoPATH file. If no logoPATH is provided or if the file cannot be found at
# specified path, default to either the Software Update or App Store Icon.
if [[ -z "$logoPath" ]] || [[ ! -f "$logoPath" ]]; then
  logDateHeader "No logo path provided or no logo exists at specified path, using standard application icon"
  if [[ -f "/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns" ]]; then
    logoPath="/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns"
  else
    logoPath="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
  fi
fi

# Collecting current user attributes ###
currentUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{print $3}')
currentUserUID=$(/usr/bin/id -u "$currentUser")
currentUserHomeDirectoryPath="$(dscl . -read /Users/$currentUser NFSHomeDirectory | awk -F ': ' '{print $2}')"

# Collect the OS version in various formats
# macOSVersionMarketingCompatible is the commerical version number of macOS (10.x, 11.x)
# macOSVersionEpoch is the major version number and is meant to draw a line between Big Sur and all prior versions of macOS
# macOSVersionMajor is the current dot releaes of macOS (15 in 10.15)

macOSVersionMarketingCompatible="$(sw_vers -productVersion)"
macOSVersionEpoch="$(awk -F '.' '{print $1}' <<<"$macOSVersionMarketingCompatible")"
macOSVersionMajor="$(awk -F '.' '{print $2}' <<<"$macOSVersionMarketingCompatible")"

# Function declarations

# checkBatteryStatus checks the charge on the battery if battery is the power source. If we're at below 25% we throw the user an error
# checkavailableDiskSpaceAPFS checks the available free space in bytes on APFS volumes. It's recommended to use Jamf smart groups to find clients with enough free space but we can accurately collect this dynamically as long as the underlying filesystem is APFS
# downloadOSInstaller will check for a current version of the OS installer on disk and download a fresh copy from either Apple or JamfCloud
# passwordpromptAppleSilicon prompts the user for their credential to authenticate software installs on Aople Silicon
# startOSInstaller starts the startosinstall process with all arguments collected during the rest of this script execution

preUpgradeJamfPolicies()
{
  jamfPolicyEvents=(
    ""
  )

  if [[ "${jamfPolicyEvents[*]}" = "" ]]; then
    logDateHeader "No Jamf policies specified, continuing"
  else
    for jamfPolicy in "${jamfPolicyEvents[@]}"; do
      logDateHeader "Running Jamf policy with event name $jamfPolicy prior to macOS Install"
      /usr/local/bin/jamf policy -event "$jamfPolicy" -verbose
    done
  fi
}

resetIgnoredUpdates()
{
  ignoredUpdates=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist InactiveUpdates)
  if [[ "$ignoredUpdates" =~ "macOS" ]] && [[ $macOSVersionEpoch -eq "10" ]]; then
    logDateHeader "at least one major upgrade is being ignored, resetting now to guarantee successful download from Apple CDN"
    softwareupdate --reset-ignored
  fi
}

networkLinkEvaluationSysDiagnose()
{
  if [[ "$networkLinkEvaluation" = "false" ]] || [[ "$networkLinkEvaluation" = "" ]]; then
    logDateHeader "Network link evaluation set to false, skipping"
  elif [[ ! -f /usr/bin/sysdiagnose ]]; then
    logDateHeader "sysdiagnose is not present, skipping network evaluation"
  else
    shui -x -n \
    -i "$logoPath" \
    -t "Checking Network" \
    -g "60" \
    -p "Performing initial network check. If the network is slow or fails certain reachability checks you'll be asked to try another Wi-Fi network..."
    if [[ -e /var/tmp/sysdiagnose.preInstall.$(date "+%m.%d.%y") ]]; then
      logDateHeader "sysdiagnose file already exists for today, using that instead"
    else
      sysdiagnose -v -A sysdiagnose.preInstall."$(date "+%m.%d.%y")" -n -F -S -u -Q -b -g -R
      # Gather Network State Details
      diagnosticsConfiguration="/var/tmp/sysdiagnose.preInstall.$(date "+%m.%d.%y")/WiFi/diagnostics-configuration.txt"
      wifiSignalState=$(grep "Poor Wi-Fi Signal" "$diagnosticsConfiguration" | grep -c "Yes")
      legacyWifiState=$(grep "Legacy Wi-Fi Rates (802.11b)" "$diagnosticsConfiguration" | grep -c "Yes")
      iosHotspotState=$(grep "iOS Personal Hotspot" "$diagnosticsConfiguration" | grep -c "Yes")
      # Gather Network Reachability Details
      diagnosticsConnectivity="/var/tmp/sysdiagnose.preInstall.$(date "+%m.%d.%y")/WiFi/diagnostics-connectivity.txt"
      appleCurlResult=$(grep "Curl Apple" "$diagnosticsConfiguration" | grep -c "No")
      appleReachabilityResult=$(grep "Reach Apple" "$diagnosticsConfiguration" | grep -c "No")
      dnsResolutionResult=$(grep "Resolve DNS" "$diagnosticsConfiguration" | grep -c "No")
      wanPingResult=$(head -1 "$diagnosticsConfiguration" | grep "Ping WAN" "$diagnosticsConfiguration" | grep -c "No")
      lanPingResult=$(head -1 "$diagnosticsConfiguration" | grep "Ping LAN" "$diagnosticsConfiguration" | grep -c "No")
      # Gather Network Congestion Details
      diagnosticsEnvironment="/var/tmp/sysdiagnose.preInstall.$(date "+%m.%d.%y")/WiFi/diagnostics-environment.txt"
      congestedNetworkResult=$(grep "Congested Wi-Fi Channel" "$diagnosticsEnvironment" | grep -c "Yes")
      # Echo all results
      logDateHeader "Wi-Fi Signal Result=$wifiSignalState"
      logDateHeader "Legacy Wi-Fi Result=$legacyWifiState"
      logDateHeader "iOS Hotspot Result=$iosHotspotState"
      logDateHeader "captive.apple.com curl Result=$appleCurlResult"
      logDateHeader "apple.com reachability Result=$appleReachabilityResult"
      logDateHeader "DNS Resolution Result=$dnsResolutionResult"
      logDateHeader "WAN Ping Result=$wanPingResult"
      logDateHeader "LAN Ping Result=$lanPingResult"
      logDateHeader "Congested Network Result=$congestedNetworkResult"
      chown -R root:admin /var/tmp/sysdiagnose.preInstall."$(date "+%m.%d.%y")"
      chmod -R 700 /var/tmp/sysdiagnose.preInstall."$(date "+%m.%d.%y")"
    fi
    if [[ "$currentUser" = "root" ]]; then
      logDateHeader "Nobody logged in, suppressing network link results"
    else
      if [[ "$congestedNetworkResult" -eq 1 ]]; then
        logDateHeader "Network link is congested, suggest to the user they close the distance between them and the Wi-fi router"
        shui -x \
        -i "$logoPath" \
        -t "Network Congestion Warning" \
        -p "Your current Wi-Fi network appears to be congested. Please move as close as possible to your Wi-Fi router for the duration of the upgrade" \
        -b "OK"
      fi
      if [[ "$wifiSignalState" -eq 1 ]]; then
        logDateHeader "Network link is weak, suggest to the user that they move as close as possible to the Wi-Fi source"
        shui -x \
        -i "$logoPath" \
        -t "Network" \
        -p "Your current Wi-Fi signal appears to be weaker than normal. Please move as close as possible to your Wi-Fi router for the duration of the upgrade" \
        -b "OK"
      fi
      if [[ "$iosHotspotState" -eq 1 ]]; then
        logDateHeader "Network link is a hotspot, warning the user to try again later"
        shui -x \
        -i "$logoPath" \
        -t "Network Hotspot Warning" \
        -p "OS Upgrades are not supported on personal hotspot networks. Please try again later on another Wi-Fi network" \
        -b "Stop"
        exit 2
      fi
      if [[ "$appleCurlResult" -eq 1 ]] || [[ "$appleReachabilityResult" -eq 1 ]] || [[ "$dnsResolutionResult" -eq 1 ]]; then
        logDateHeader "Connectivity to Apple's servers and/or DNS resolution tests failed on this network, suggesting to the user they try again later on a different network"
        shui -x \
        -i "$logoPath" \
        -t "Network Reachability Warning" \
        -p "This network doesn't appear to support Apple software updates, please try another Wi-Fi network" \
        -b "Stop"
        exit 2
      fi
    fi
  fi
}

networkLinkEvaluationMontereyStyle()
{
  networkQualityResultsJSON="$(networkQuality -c -s -v)"
  networkQualityTestStartDate=$(getJsonValue "$networkQualityResultsJSON" .start_date)
  networkQualityTestEndDate=$(getJsonValue "$networkQualityResultsJSON" .end_date)
  downloadResponsiveness=$(getJsonValue "$networkQualityResultsJSON" .dl_responsiveness)
  downloadThroughputInBits=$(getJsonValue "$networkQualityResultsJSON" .dl_throughput)
  # TODO - Get Error Codes Here
}

checkBatteryStatus()
{
  getcurrentPowerDrawStatus(){
    currentPowerDrawStatus=$(pmset -g batt | head -n 1)
  }
  getcurrentPowerDrawStatus
  if [[ "$currentPowerDrawStatus" =~ "Now drawing from 'Battery Power'" ]]; then
    batteryMaximumCapacity=$(ioreg -r -c "AppleSmartBattery" | grep '"MaxCapacity"' | tail -n 1 | awk -F ' = ' '{print $2}')
    batteryCurrentCapacity=$(ioreg -r -c "AppleSmartBattery" | grep '"CurrentCapacity"' | tail -n 1 | awk -F ' = ' '{print $2}')
    batteryPercentage=$(echo "scale=4; ($batteryCurrentCapacity / $batteryMaximumCapacity) * 100" | bc | awk -F '.' '{print $1}')
    if [ "$batteryPercentage" -lt 50 ]; then
      logDateHeader "warning the user to plug into an AC power source before continuing"
      if [[ "$currentUser" = "root" ]]; then
        logDateHeader "Nobody logged in, suppressing battery results"
      else
        shui -x \
          -i "$logoPath" \
          -t "Battery Warning" \
          -p "Not enough charge remains in your battery to continue. Please plug your Mac into a wall outlet and try again" \
          -b "OK"
        until [[ "$currentPowerDrawStatus" =~ "AC Power" ]]; do
          sleep 10
          getcurrentPowerDrawStatus
        done
      fi
    else
      logDateHeader "Battery level currently at $batteryPercentage, proceeding"
    fi
  fi
}

checkAvailableDiskSpace()
{
  availableDiskSpaceBytes=$(diskutil info / | grep -E 'Container Free Space|Volume Free Space|Volume Available Space' | awk '{print $6}' | sed "s/(//")
  availableDiskSpaceMeasure=$(diskutil info / | grep -E 'Container Free Space|Volume Free Space|Volume Available Space' | awk '{print $5}')
  if [[ "$availableDiskSpaceMeasure" = "TB" ]]; then
    logDateHeader "at least 1 TB of space is available, continuing"
    willNotifyDiskSpaceWarning="false"
  elif [[ "$availableDiskSpaceMeasure" = "GB" && "$availableDiskSpaceBytes" -ge "48000000000" ]]; then
    logDateHeader "at least 48 GB of space is available, enough free space for any OS upgrade, continuing"
    willNotifyDiskSpaceWarning="false"
  elif [[ "$installerName" = "Install macOS Catalina" && "$macOSVersionMajor" -le "10" ]]; then
    logDateHeader "Yosemite or earlier requires at least 19GB of free space + the 10GB needed for the installer, checking"
    if [[ "$availableDiskSpaceBytes" -ge "29000000000" ]]; then
      logDateHeader "at least 29GB of space is available, continuing"
      willNotifyDiskSpaceWarning="false"
    else
      logDateHeader "not enough free disk space to perform the upgrade, letting the user know and exiting"
      willNotifyDiskSpaceWarning="true"
    fi
  elif [[ "$installerName" = "Install macOS Catalina" && "$macOSVersionMajor" -ge "11" ]]; then
    logDateHeader "El Capitan or greater requires at least 13GB of free space + the 10GB needed for the installer, checking"
    if [[ "$availableDiskSpaceBytes" -ge "23000000000" ]]; then
      logDateHeader "at least 23GB of space is available, continuing"
      willNotifyDiskSpaceWarning="false"
    else
      logDateHeader "not enough free disk space to perform the upgrade, letting the user know and exiting"
      willNotifyDiskSpaceWarning="true"
    fi
  elif [[ "$installerName" = "Install macOS Big Sur" || "$installerName" = "Install macOS Monterey" ]] && [[ "$macOSVersionMajor" -ge "12" ]]; then
    logDateHeader "Sierra or greater requires at least 36GB of free space + the 12GB needed for the installer, checking"
    if [[ "$availableDiskSpaceBytes" -ge "48000000000" ]]; then
      logDateHeader "at least 48GB of space is available, continuing"
      willNotifyDiskSpaceWarning="false"
    else
      logDateHeader "not enough free disk space to perform the upgrade, letting the user know and exiting"
      willNotifyDiskSpaceWarning="true"
    fi
  elif [[ "$installerName" = "Install macOS Big Sur" || "$installerName" = "Install macOS Monterey" ]] && [[ "$macOSVersionMajor" -lt "12" ]]; then
    logDateHeader "El Capitan or earlier requires at least 45GB of free space + the 12GB needed for the installer, checking"
    if [[ "$availableDiskSpaceBytes" -ge "57000000000" ]]; then
      logDateHeader "at least 57GB of space is available, continuing"
      willNotifyDiskSpaceWarning="false"
    else
      logDateHeader "not enough free disk space to perform the upgrade, letting the user know and exiting"
      willNotifyDiskSpaceWarning="true"
    fi
  fi
  if [[ "$willNotifyDiskSpaceWarning" = "true" && "$currentUser" != "root" ]]; then
    shui  \
    -i "$logoPath" \
    -t "Disk Space Warning" \
    -p "Not enough disk space remains to perform the upgrade. You can review your space from the Apple Menu -> About this Mac -> Storage -> Manage." \
    -b "Review Storage" \
    -g 300
    if [[ -d "/System/Library/CoreServices/Applications/Storage Management.app" ]]; then
      /bin/launchctl asuser "$currentUserUID" open -a "/System/Library/CoreServices/Applications/Storage Management.app"
      exit $?
    else
      /bin/launchctl asuser "$currentUserUID" open "https://support.apple.com/en-us/HT206996#manually"
      exit $?
    fi
  elif [[ "$willNotifyDiskSpaceWarning" = "true" && "$currentUser" = "root" ]]; then
    logDateHeader "nobody logged in, skipping notifications, but not enough disk space remains to do the update"
    exit $?
  fi
}

checkForRunningSoftwareUpdate()
{
  if pgrep -x startosinstall; then
    logDateHeader "another startosinstall operation is in progress, stopping that one and cleaning up"
    pkill -x startosinstall
    if [[ -d /Volumes/InstallESD ]]; then
      logDateHeader "Unmounting InstallESD in preparation for new install"
      diskutil unmount /Volumes/InstallESD
    fi
    if [[ -d /Volumes/"Shared Support" ]]; then
      logDateHeader "Unmounting Shared Support in preparation for new install"
      diskutil unmount /Volumes/"Shared Support"
    fi
  fi
  if pgrep -x softwareupdate; then
    logDateHeader "another softwareupdate operation is in progress, stopping that one and HUPing the process"
    pkill -x softwareupdate
    launchctl kickstart -k system/com.apple.softwareupdated
    sleep 5
  fi
}

downloadOSInstaller()
{
  autoload is-at-least
  installerCount="$(mdfind -name "$installerName" | grep \.app$ | grep -v "/Library/Application Support/JAMF" | wc -l | sed "s/^[ \t]*//")"
  if [[ "$installerCount" -eq "0" ]]; then
    logDateHeader "No installers present, downloading a fresh copy"
    installerPath="/Applications/$installerName.app"
    startOSInstall="$installerPath"/Contents/Resources/startosinstall
    installerIcon="$installerPath"/Contents/Resources/InstallAssistant.icns
    willDownload="true"
  elif [[ "$installerCount" -ge "1" ]]; then
    while read -r -d '' line; do
      if [[ "${line}" == *'.app' && "${line}" != '/Library/Application Support/JAMF'* ]]; then
        logDateHeader "Found installers at "${line}", checking version"
        macOSInstallerCurrentBundleVersion="$(/usr/libexec/PlistBuddy -c "Print:CFBundleShortVersionString" "${line}"/Contents/Info.plist)"
        if ! is-at-least "$macOSPreferredBundleVersion" "$macOSInstallerCurrentBundleVersion"; then
          logDateHeader "Version on disk does not match or is older then the preferred version, removing"
          rm -rdf "${line}"
          installerPath="/Applications/$installerName.app"
          startOSInstall="$installerPath"/Contents/Resources/startosinstall
          installerIcon="$installerPath"/Contents/Resources/InstallAssistant.icns
          willDownload="true"
        else
          logDateHeader "Version of installer at "${line}" matches or is newer than the preferred version, continuing"
          installerPath="${line}"
          startOSInstall="${line}"/Contents/Resources/startosinstall
          installerIcon="${line}"/Contents/Resources/InstallAssistant.icns
          willDownload="false"
          networkLinkEvaluation="false"
        fi
      fi
    done < <(mdfind -name "$installerName" -0)
  fi
  if [[ "$macOSVersionMajor" -ge "15" ]] || [[ "$macOSVersionEpoch" -ge "11" ]] && [[ "$willDownload" = "true" ]]; then
    logDateHeader "Installer will be requested from Apple CDN, checking if network link evaluations are allowed"
    networkLinkEvaluation
    logDateHeader "macOS version eligible for Install macOS App via softwareupdate, attempting download now..."
    if [[ "$currentUser" = "root" || "$runHeadless" = "true" ]]; then
      logDateHeader "Suppressing download notification"
    else
      shui \
      -i "$logoPath" \
      -t "Downloading macOS" \
      -p "Downloading a new copy of macOS. This can take some time. You can close this window and we'll let you know when it's ready" \
      -b "OK" &
    fi
    if softwareupdate --fetch-full-installer --full-installer-version "$macOSDownloadVersion"; then
      logDateHeader "Download from Apple CDN was successful"
      chflags hidden $installerPath
    else
      isMajorOSUpdateDeferred=$(system_profiler SPConfigurationProfileDataType | grep -c enforcedSoftwareUpdateMajorOSDeferredInstallDelay)
      if [[ "$isMajorOSUpdateDeferred" -ge "1" ]]; then
        logDateHeader "Major OS Update Deferral is in effect, are you sure you're requesting an installer outside your deferral window?"
      fi
      logDateHeader "Download from Apple CDN was not successfull, falling back to Jamf download if available"
      if [[ "$macOSInstallAppJamfEvent" != "" ]]; then
        if ! /usr/local/bin/jamf policy -event "$macOSInstallAppJamfEvent"; then
          logDateHeader "Installer could not be downloaded from Jamf, bailing now"
          exit 1
        fi
      else
        logDateHeader "Download from Apple CDN and Jamf repositories were not successfull, bailing"
        exit 1
      fi
    fi
  fi
  if [[ "$macOSVersionMajor" -lt "15" ]] && [[ "$macOSVersionEpoch" -lt "11" ]] && [[ "$willDownload" = "true" ]]; then
    logDateHeader "Installer will be requested from Jamf CDN, checking if Jamf event variable is populated"
    if [[ "$macOSInstallAppJamfEvent" = "" ]]; then
      logDateHeader "Jamf Event is not defined in policy, bailing"
      exit 2
    fi
    logDateHeader "Checking if network link evaluations are allowed"
    networkLinkEvaluationSysDiagnose
    logDateHeader "macOS version must be downloaded via Jamf Policy, attempting download now..."
    if [[ "$currentUser" = "root" ]]; then
      logDateHeader "Nobody logged in, suppressing download notification"
    else
      shui -n -x \
      -i "/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns" \
      -t "Downloading macOS" \
      -p "Downloading a new copy of macOS. This can take some time. You can close this window and we'll let you know when it's ready" \
      -b "OK"
    fi
    if /usr/local/bin/jamf policy -event "$macOSInstallAppJamfEvent"; then
      logDateHeader "Installer successfully downloaded from Jamf repository"
      chflags hidden $installerPath
    else
      logDateHeader "Installer could not be downloaded from Jamf, bailing now"
      exit 1
    fi
  fi
}

passwordPromptAppleSilicon()
{
  if [[ "$currentUser" = "root" ]]; then
    logDateHeader "macOS on Apple Silicon cannot be upgraded without an active login, bailing"
    exit 0
  elif [[ ! -z "$localAdminPasswordForHeadlessInstalls" ]]; then
    userPassword="$localAdminPasswordForHeadlessInstalls"
  else
    logDateHeader "Prompting $currentUser for their new password..."
    eval "$(shui text -x -v -p "Please enter your password to start the upgrade..." -h -i $logoPath -b "OK")"
    userPassword="$lastText"
    # Check the user's password against the local Open Directory store
    TRY=1
    while ! /usr/bin/dscl /Search -authonly "$currentUser" "$userPassword"; do
      ((TRY++))
      logDateHeader "Prompting $currentUser for their Mac password again attempt $TRY..."
      eval "$(shui -x -v text -v -p "Please re-type your password" -h -i $logoPath)"
      userPassword="$lastText"
      if ! /usr/bin/dscl /Search -authonly "$currentUser" "$userPassword"; then
        if (( $TRY >= 2 )); then
          logDateHeader "[ERROR] Password prompt unsuccessful after 2 attempts. Displaying \"forgot password\" message..."
          shui -x \
          -i "$logoPath" \
          -t "Authentication Problem" \
          -p "Your password seems to be incorrect. Verify that you are using the correct password for Mac authentication and try again..." \
          -b "Stop" &
          exit 1
        fi
      fi
    done
  fi
}

passwordPromptAPFSConversion()
{
  if [[ ! -z "$localAdminPasswordForHeadlessInstalls" ]]; then
    userPassword="$localAdminPasswordForHeadlessInstalls"
  else
    logDateHeader "Prompting $currentUser for their new password..."
    eval "$(shui -x -v text -v -p "Please enter your password to start the upgrade..." -h -i $logoPath)"
    userPassword="$lastText"
    # Check the user's password against the local Open Directory store
    TRY=1
    while ! /usr/bin/dscl /Search -authonly "$currentUser" "$userPassword"; do
      ((TRY++))
      logDateHeader "Prompting $currentUser for their Mac password again attempt $TRY..."
      eval "$(shui -x -v text -v -p "Please re-type your password" -h -i $logoPath)"
      userPassword="$lastText"
      if ! /usr/bin/dscl /Search -authonly "$currentUser" "$userPassword"; then
        if (( $TRY >= 2 )); then
          logDateHeader "[ERROR] Password prompt unsuccessful after 2 attempts. Displaying \"forgot password\" message..."
          shui -x \
          -i "$logoPath" \
          -t "Authentication Problem" \
          -p "Your password seems to be incorrect. Verify that you are using the correct password for Mac authentication and try again..." \
          -b 'Stop' &
          exit 1
        fi
      fi
    done
  fi
}

startOSInstaller()
{
  finalRebootWarning(){
    while pgrep -x "sleep"; do
      sleep 1
    done
    shui -v -x \
    -i "$installerIcon" \
    -t "Restarting Now" \
    -p "Your Mac will reboot now to start the update process. Your screen may turn on and off several times during the update. This is normal. Please do not press the power button during the update." \
    -b "OK" \
    -g 60
    while pgrep -q osascript; do
      sleep 1
    done
    if pgrep "Self Service"; then
      logDateHeader "Self Service is open, killing now to prevent a reboot delay"
      pkill "Self Service"
    fi
  }

  installerStartTimeHourlyPrecision=$(/bin/date "+%Y-%m-%d %H")
  startOSInstallOptions=$($startOSInstall --usage 2>&1 | grep ',' | awk -F ',' '{print $1}')
  if [[ -d /Volumes/InstallESD ]]; then
    logDateHeader "Unmounting InstallESD in preparation for new install"
    diskutil unmount /Volumes/InstallESD
  fi
  if [[ -d /Volumes/"Shared Support" ]]; then
    logDateHeader "Unmounting Shared Support in preparation for new install"
    diskutil unmount /Volumes/"Shared Support"
  fi
  find /private/var/folders/*/*/C/com.apple.mdworker.bundle -mindepth 1 -delete
  find /private/var/folders/*/*/C/com.apple.metadata.mdworker -mindepth 1 -delete
  shui -x -v -n \
  -i "$logoPath" \
  -t "Preparing macOS Install" \
  -b "OK" \
  -p "Your macOS installation is being prepared. You can continue working and we'll notify you when it's time to restart..."
  sleep 3600 &
  sleepPID=$(pgrep -n sleep)
  finalRebootWarning &
  if [[ "$installAction" = "erase" ]] && [[ $willRequireAppleSiliconPassword = "true" || $willRequireAPFSConversionPassword = "true" ]]; then
    echo "$userPassword" | "$startOSInstall" --eraseinstall --newvolumename 'Macintosh HD' --pidtosignal $sleepPID --agreetolicense --rebootdelay "60" --user "$currentUser" --stdinpass
  elif [[ "$installAction" = "reinstall" ]] || [[ "$installAction" = "upgrade" ]] && [[ $willRequireAppleSiliconPassword = "true" || $willRequireAPFSConversionPassword = "true" ]]; then
    echo "$userPassword" | "$startOSInstall" --agreetolicense --pidtosignal $sleepPID --rebootdelay "60" --user "$currentUser" --stdinpass
  elif [[ "$installAction" = "erase" ]] && [[ $willRequireAppleSiliconPassword = "false" || $willRequireAPFSConversionPassword = "false" ]]; then
    "$startOSInstall" --eraseinstall --newvolumename 'Macintosh HD' --pidtosignal $sleepPID --agreetolicense --rebootdelay "60"
  elif [[ "$installAction" = "reinstall" ]] || [[ "$installAction" = "upgrade" ]] && [[ $willRequireAppleSiliconPassword = "false" || $willRequireAPFSConversionPassword = "false" ]]; then
    "$startOSInstall" --agreetolicense --pidtosignal $sleepPID --rebootdelay "60"
  fi
  grep "$installerStartTimeHourlyPrecision" /var/log/install.log
}

startOSInstallerHeadless()
{
  installerStartTimeHourlyPrecision=$(/bin/date "+%Y-%m-%d %H")
  if [[ -d /Volumes/InstallESD ]]; then
    echo "Unmounting InstallESD in preparation for new install"
    diskutil unmount /Volumes/InstallESD
  fi
  if [[ -d /Volumes/"Shared Support" ]]; then
    echo "Unmounting Shared Support in preparation for new install"
    diskutil unmount /Volumes/"Shared Support"
  fi
  find /private/var/folders/*/*/C/com.apple.mdworker.bundle -mindepth 1 -delete
  find /private/var/folders/*/*/C/com.apple.metadata.mdworker -mindepth 1 -delete
  if [[ "$installAction" = "erase" ]] && [[ $willRequireAppleSiliconPassword = "true" || $willRequireAPFSConversionPassword = "true" ]]; then
    echo "$userPassword" | "$startOSInstall" --eraseinstall --newvolumename 'Macintosh HD' --pidtosignal startosinstall --agreetolicense --rebootdelay "60" --user "$currentUser" --stdinpass --forcequitapps
  elif [[ "$installAction" = "reinstall" ]] || [[ "$installAction" = "upgrade" ]] && [[ $willRequireAppleSiliconPassword = "true" || $willRequireAPFSConversionPassword = "true" ]]; then
    echo "$userPassword" | "$startOSInstall" --agreetolicense --rebootdelay "60" --pidtosignal startosinstall --user "$currentUser" --stdinpass --forcequitapps
  elif [[ "$installAction" = "erase" ]] && [[ $willRequireAppleSiliconPassword = "false" || $willRequireAPFSConversionPassword = "false" ]]; then
    "$startOSInstall" --eraseinstall --newvolumename 'Macintosh HD' --pidtosignal startosinstall --agreetolicense --rebootdelay "60" --forcequitapps
  elif [[ "$installAction" = "reinstall" ]] || [[ "$installAction" = "upgrade" ]] && [[ $willRequireAppleSiliconPassword = "false" || $willRequireAPFSConversionPassword = "false" ]]; then
    "$startOSInstall" --agreetolicense --rebootdelay "60" --pidtosignal startosinstall --forcequitapps
  fi
  grep "$installerStartTimeHourlyPrecision" /var/log/install.log
}

eraseAllContentsAndSettings()
{
  iBridgeType=$(system_profiler SPiBridgeDataType | grep "Model Name" | awk -F ': ' '{print $2}')
  if [[ "$macOSVersionEpoch" -lt "12" ]]; then
    logDateHeader "erase all contents and settings is only available on macOS 12 or higher"
  elif [[ "$iBridgeType" == "Apple T1 Security Chip" ]]; then
    logDateHeader "erase all contents and settings is only available on T2 chip or higher hardware models"
  else
    if [[ $(groups "$currentUser" | grep -c " admin ") -eq "0" ]]; then
      logDateHeader "user must be an administrator to perform an erase all contents and settings, notifying user"
      shui  \
    	-i "$logoPath" \
    	-t "Privileges Warning" \
    	-p "You must be an Administrator to perform an Erase all Contents and Settings. Elevate your rights using your usual privilege elevation tool or speak to technical support." \
    	-b "Review Storage"
    else
    	open "/System/Library/CoreServices/Erase Assistant.app"
    fi
  fi
}

if [[ "$installAction" = "eacas" ]]; then
  logDateHeader "triggering iOS style EACAS action"
  eraseAllContentsAndSettings
  exit $?
fi

if [[ "$currentUser" = "root" ]]; then
  logDateHeader "Nobody is logged in, assume runheadless and proceed as far as we can without an interactive session"
  runHeadless="true"
fi

checkBatteryStatus
checkAvailableDiskSpace
preUpgradeJamfPolicies
resetIgnoredUpdates
checkForRunningSoftwareUpdate
downloadOSInstaller

# Check which install action was set by Jamf Policy and change the notification language
# appropriately

if [[ "$installAction" = "erase" ]]; then
  rebootActionTitle="Erase and Install macOS"
  rebootActionDescription="Your Mac will be erased and re-installed. Please do so only after performing a backup of your important files."
elif [[ "$installAction" = "reinstall" || "$installAction" = "" ]]; then
  rebootActionTitle="Re-install macOS"
  rebootActionDescription="Your Mac will have a new copy of macOS installed. All of your files and settings will be preserved. Expected install time is approximately 20-30 minutes..."
elif [[ "$installAction" = "upgrade" ]]; then
  rebootActionTitle="Upgrade macOS"
  rebootActionDescription="Your Mac will be upgraded to the latest version of macOS. All of your files and settings will be preserved. Expected upgrade time is approximately 20-40 minutes..."
elif [[ "$installAction" = "downloadonly" ]]; then
  logDateHeader "Download only was selected, bailing out"
  exit $?
fi

startingFileSystemPersonality=$(diskutil info / | awk '/File System Personality/' | awk -F ':' '{print $2}' | sed "s/^[ \t]*//")
if [[ $startingFileSystemPersonality != "APFS" ]]; then
  logDateHeader "Filesystem conversion will require a name and password challenge"
  willRequireAPFSConversionPassword="true"
else
  willRequireAPFSConversionPassword="false"
fi

if [[ $(sysctl -in hw.optional.arm64) == "1" ]]; then
  logDateHeader "system is Apple silicon architecture, will require name and password challenge"
  willRequireAppleSiliconPassword="true"
else
  willRequireAppleSiliconPassword="false"
fi

if [[ "$runHeadless" = "true" ]]; then
  logDateHeader "skipping reboot notification as we are running headless"
  if [[ $willRequireAppleSiliconPassword = "true" ]]; then
    passwordPromptAppleSilicon
    startOSInstallerHeadless
  elif [[ $willRequireAPFSConversionPassword = "true" ]]; then
    passwordPromptAPFSConversion
    startOSInstallerHeadless
  else
    startOSInstallerHeadless
  fi
else
  eval "$(shui -v -x -i "$installerIcon" -t "$rebootActionTitle" -p "$rebootActionDescription" -b "Start" -g 300)"
  rebootAction="$lastButton"
  if [[ "$rebootAction" = "Start" ]] || [[ "$lastGaveUp" = "true" ]]; then
    logDateHeader "installation continuing, checking cpu architecture"
    if [[ $willRequireAppleSiliconPassword = "true" ]]; then
      passwordPromptAppleSilicon
      startOSInstaller
    elif [[ $willRequireAPFSConversionPassword = "true" ]]; then
      passwordPromptAPFSConversion
      startOSInstaller
    else
      startOSInstaller
    fi
  fi
fi
