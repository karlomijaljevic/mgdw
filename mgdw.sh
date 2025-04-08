#!/usr/bin/env bash
#
# Copyright (C) 2025 Karlo Mijaljević
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#

# =========================== #
# ========= GLOBALS ========= #
# =========================== #

# Mangaread IP address.
g_uri_mangaread="81.17.28.130"

# Flags.
p_help=("--help" "-h")
p_version=("--version" "-v")

# Colors.
c_normal="\e[0m"
c_red="\e[1;31m"
c_green="\e[1;32m"

# Files used for downloading and saving manga. Configure at your leisure.
g_cache_dir="/home/$USER/.cache/manga-dw"
g_search_file="${g_cache_dir}/search.json"
g_index_file="${g_cache_dir}/index.html"
g_single_index_file="${g_cache_dir}/single-index.html"
g_temp_file="${g_cache_dir}/temp.txt"
g_url_file="${g_cache_dir}/urls.txt"
g_title_file="${g_cache_dir}/titles.txt"
g_image_url_file="${g_cache_dir}/clean-images.txt"
g_manga_dir="/home/$USER/Documents/manga"
g_error_log="${g_cache_dir}/error.log"

# User agent constant.
g_user_agent="Mozilla/5.0 (Windows NT 10.0; rv:127.0) Gecko/20100101 Firefox/127.0"

# Global variables that are assigned by (and used by) functions.
g_manga_name=""
g_manga_url=""
g_starting_chapter=0
g_ending_chapter=0
g_temp_images_dir=""
g_start_time=0
g_error_occurred=0

# =========================== #
# ======== FUNCTIONS ======== #
# =========================== #

# Checks for the program dependencies, which are: jq, img2pdf, aria2, curl,
# exiv2 and rename.
function f_check_dependencies {
        if command -v jq > /dev/null 2>&1 ; then
                true
        else
                echo -e "${c_red}Program 'jq' not found!$c_normal"
                exit 1
        fi

        if command -v img2pdf > /dev/null 2>&1 ; then
                true
        else
                echo -e "${c_red}Program 'img2pdf' not found!$c_normal"
                exit 2
        fi

        if command -v aria2c > /dev/null 2>&1 ; then
                true
        else
                echo -e "${c_red}Program 'aria2' not found!$c_normal"
                exit 3
        fi

        if command -v curl > /dev/null 2>&1 ; then
                true
        else
                echo -e "${c_red}Program 'curl' not found!$c_normal"
                exit 4
        fi

        if command -v rename > /dev/null 2>&1 ; then
                true
        else
                echo -e "${c_red}Program 'rename' not found!$c_normal"
                exit 4
        fi
        
        if command -v exiv2 > /dev/null 2>&1 ; then
                true
        else
                echo -e "${c_red}Program 'exiv2' not found!$c_normal"
                exit 5
        fi
}

# Parse provided flags.
function f_parse_flags {
        local flags_found=0

        for flag in "${@}";
        do
                if [ "${flag}" == "${p_help[0]}" ] || [ "${flag}" == "${p_help[1]}" ]; then
                        echo "The only flags this script accepts are:"
                        echo "--help, -h"
                        echo "--version, -v"
                        echo
                        flags_found=1
                elif [ "${flag}" == "${p_version[0]}" ] || [ "${flag}" == "${p_version[1]}" ]; then
                        echo "Program version: 1.0.0"
                        echo
                        flags_found=1
                fi
        done

        if [ $flags_found -eq 1 ]; then
                exit 0
        fi

        if [ $flags_found -eq 0 ] && [ ${#@} -gt 0 ]; then
                echo -e "${c_red}The flags you have provided are not supported!$c_normal"
                exit 6
        fi
}

# Check if the cache directory exists. If not create it.
function f_cache_dir_check {
        if [ ! -d "$g_cache_dir" ]; then
                mkdir "$g_cache_dir"
        fi
}

# Loop until the user enters a valid manga name.
function f_search_manga {
        local success="false"

        while :; do
                read -r -p "Enter manga name to download (e.g. Naruto): " name

                curl -s --compressed -X POST \
                        -A "$g_user_agent" \
                        -H "Content-Type: application/x-www-form-urlencoded" \
                        -H "Accept: application/json" \
                        -H "Host: $g_uri_mangaread" \
                        -H "Accept-Language: en-US,en;q=0.5" \
                        -H "Referer: https://$g_uri_mangaread/" \
                        -d "action=wp-manga-search-manga&title=$name" \
                        "http://$g_uri_mangaread/wp-admin/admin-ajax.php" \
                        | jq '.' > "$g_search_file"

                success="$(jq '.success' < "$g_search_file" 2>/dev/null)"

                if [ "$success" = "false" ]; then
                        echo -e "${c_red}Found nothing for manga with name: '$name'$c_normal"
                else
                        break
                fi
        done
}

# Loop until the user enters a valid manga number from the found manga titles.
function f_chose_manga {
        local modified_number=0

        while :; do
                echo
                echo "Found these titles matching/containing provided name:"

                jq -r '.data[].title' < "$g_search_file" \
                        | while read -r title; do echo "$title"; done \
                        | grep -nE '.'
                echo

                read -r -p "Choose a title by providing a matching number: " number
                
                modified_number=$(( number - 1))
                g_manga_url="$(jq -r ".data[$modified_number].url" < "$g_search_file")"
                g_manga_name="$(jq -r ".data[$modified_number].title" < "$g_search_file")"

                if [ -z "$g_manga_url" ]; then
                        echo -e "${c_red}Please enter a valid number!$c_normal"
                else
                        break
                fi
        done
}

# Download the manga index file and modify it for later functions.
# Create the URL and title files.
function f_dw_manga_index {
        aria2c --quiet \
                --header="Accept: text/html" \
                --user-agent="$g_user_agent" \
                --auto-file-renaming=false \
                --allow-overwrite=true \
                --dir="$g_cache_dir" \
                --out="index.html" \
                "$g_manga_url"
        
        awk '/<li class=\"wp-manga-chapter    \">/{f=1} /<span class\=\"chapter-release-date\">/{f=0;print} f' "$g_index_file" > "$g_temp_file"
        sed -i 's|<li class\=\"wp-manga-chapter    \">||g' "$g_temp_file"
        sed -i 's|<span class\=\"chapter-release-date\">||g' "$g_temp_file"
        sed -i '/^[[:space:]]*$/d' "$g_temp_file"
        sed -i 's/^[[:space:]]*<a/<a/g' "$g_temp_file"
        
        grep 'a href' "$g_temp_file" | sed 's|\">||g' | sed 's|<a href=\"||g' > "$g_url_file"
        grep 'Chapter' "$g_temp_file" | sed 's|[[:space:]]*</a>||g' > "$g_title_file"
        
        sed -i -r 's/^[[:space:]]*([[:alpha:]])/\1/g' "$g_title_file" 
        sed -i 's/\(:\|!\|\"\|\?\|\[\|\]\|(\|)\|\.\{1,\}\)/ /g' "$g_title_file"
        sed -i "s|'| |g" "$g_title_file"
        sed -i 's/\( \{1,\}\)/_/g' "$g_title_file"
        sed -i 's|_$||g' "$g_title_file"
}

# List the titles for the user together with an explanation message
# The user must chose a valid chapter order!
function f_show_and_chose_chapters {
        echo
        echo "Titles found:"
        tac "$g_title_file" | grep -En "[0-9]+"
        echo
        echo "Choose a chapter to start from and then a chapter to end to. In case you don't choose a starting chapter the chapters will go from first until the end choice. In case you don't choose an ending chapter they will go from the chosen to the final chapter (currently available). If you choose no starting and no ending chapter all the chapters will be downloaded. Lastly if you choose the same chapter twice, only that chapter will be downloaded. Duly note that you should NOT enter chapter numbers but the numbers on the left of the chapters."
        
        while :; do
                read -r -p "Where to start from (inclusive): " g_starting_chapter
                read -r -p "Where to end to (inclusive): " g_ending_chapter
                echo

                if [ -z "$g_starting_chapter" ]; then
                        g_starting_chapter=1
                fi

                if [ -z "$g_ending_chapter" ]; then
                        g_ending_chapter="$(wc -l < "$g_title_file")"
                fi

                if [ "$g_ending_chapter" -lt "$g_starting_chapter" ]; then
                        echo -e "${c_red}Starting chapter can't be less than ending chapter!$c_normal"
                else
                        break;
                fi
        done
}

# Check if the user configured manga directory exists. If not create it.
function f_configure_manga_dir {
        local manga_dir=""

        if [ ! -d "$g_manga_dir" ]; then
                echo "Manga directory missing. Creating it now."
                mkdir "$g_manga_dir"
                echo "Manga directory created."
        fi

        manga_dir="$g_manga_dir/$g_manga_name"

        if [ ! -d "$manga_dir" ]; then
                echo "$g_manga_name manga directory missing. Creating it now."
                mkdir "$manga_dir"
                echo "$g_manga_name manga directory created."
        fi
}

# Start downloading the selected chapter/s.
function f_dw_manga {
        if [ "$g_starting_chapter" = "$g_ending_chapter" ]; then
                f_dw_chapter "$g_starting_chapter" "$g_manga_name"
        else
                echo "Downloading $g_manga_name chapters from $g_starting_chapter to $g_ending_chapter"
                        
                for ((i = g_starting_chapter ; i <= g_ending_chapter ; i++));
                do
                        f_dw_chapter "$i" "$g_manga_name"
                done
        fi
}

# Downloads the chosen manga chapter from the list of URLs
function f_dw_chapter {
        echo
        local start="$1"
        local name="$2"
        local current_dir=""
        local chapter_name=""
        local referer_header=""
        local image_metadata=""
        
        g_temp_images_dir="$g_manga_dir/$name/$start"

        if [ -d "$g_temp_images_dir" ]; then
                rm -rf "${g_temp_images_dir:?}/" 
        fi

        mkdir "$g_temp_images_dir"
        
        chapter_name="$(tac "$g_title_file" | sed "${start}q;d")"
        chapter_name="$(echo "$chapter_name" | sed 's/\//_/g')"

        aria2c --quiet \
                --user-agent="$g_user_agent" \
                --header="Accept: text/html" \
                --auto-file-renaming=false \
                --allow-overwrite=true \
                --dir="$g_cache_dir" \
                --out="single-index.html" \
                "$(tac "$g_url_file" | head -"$start" | tail -1)"

        awk '/<div class=\"page\-break no\-gaps\">/{f=1} /<\/div>/{f=0;print} f' "$g_single_index_file" \
                | grep 'https://www.mangaread.org/wp-content/uploads/WP-manga/' "$g_single_index_file" \
                | sed 's|\s||g' \
                | sed 's|\"class=\"wp\-manga\-chapter\-img\">||g'  > "$g_image_url_file"
        
        referer_header="Referer: https://$g_uri_mangaread/"

        echo "Starting to download the images for '$chapter_name' chapter."
        aria2c --quiet \
                --max-concurrent-downloads=10 \
                --max-connection-per-server=10 \
                --header="Accept: image/*" \
                --header="$referer_header" \
                --user-agent="$g_user_agent" \
                --input-file="$g_image_url_file" \
                --dir="$g_temp_images_dir"
        echo "Images downloaded successfully."

        current_dir="$(pwd)"
        cd "$g_temp_images_dir" || exit
        
        echo "Checking downloaded images."
        for file in *; do
                if [ -f "$file" ]; then
                        exiv2 "$file" 1>/dev/null 2>stderr.txt
                        image_metadata="$(cat stderr.txt)"
                        if [[ "$image_metadata" =~ .*"exception".* ]]; then
                                rm "$file"
                        fi
                fi
        done
        rm stderr.txt
        echo "All downloaded images successfully checked."

        rename -f 's/^[a-z_\-]+//' ./*
        rename -f "s/${start}_//" ./*

        find ./ -type f | sed 's|\./||g' | sort --general-numeric-sort \
                | while read -r number; do echo "$(pwd)/$number" >> "paths.txt"; done
        tr '\n' '\0' < "paths.txt" > "clean-paths.txt"

        echo "Starting to create '$chapter_name' chapter."
        if img2pdf --from-file "clean-paths.txt" -o "$g_manga_dir/$name/$chapter_name.pdf" 2>>"$g_error_log"; then
                echo -e "${c_green}Chapter '$chapter_name' created successfully.$c_normal"
        else
                echo -e "${c_red}FAILED to download chapter \"$chapter_name\"! Details can be viewed in the $g_error_log file.$c_normal"
                echo "" >> "$g_error_log"
                g_error_occurred=$((g_error_occurred+1))
        fi
        
        cd "$current_dir" || exit

        echo "Removing temporary chapter directory."
        rm -rf "${g_temp_images_dir:?}/"
        
        return 
}

# Removes special and unnecessary characters
function f_fix_chapter_names {
        local current_dir=""

        echo
        echo "Performing chapter name fixes."
        
        current_dir="$(pwd)"
        cd "$g_manga_dir/$g_manga_name" || exit

        rename -f 's/\-/_/g' ./*
        rename -f 's/[_\-]{2,}/_/g' ./*
        rename -f "s/[\:’\'\,\[\]\?\!\~\#]//g" ./*
        rename -f 's/\.\/_//' ./*
        rename -f 's/Vol_[0-9]+_//' ./*

        cd "$current_dir" || exit

        echo -e "${c_green}Chapter names cleaned from unnecessary characters!$c_normal"
}

# Removes the cache directory and any leftover temporary files. Either 
# after the program completes or when SIGINT is sent by the user. And
# exits the application with an exit code of '0'.
# Accepts one argument, either a 0 (default if none provided) or a 1.
# If 0 is provided then the application will not exit only clean 
# directories. If 1 is provided it will clean directories and exit.
function f_clean_trash {
        local end_time=0
        local runtime=0
        local is_exit=0

        if [ $g_error_occurred -eq 0 ]; then
                if [ -d "$g_cache_dir" ]; then
                        rm -rf "${g_cache_dir:?}/"
                        echo
                fi

                if [ -d "$g_temp_images_dir" ]; then
                        rm -rf "${g_temp_images_dir:?}/"
                        echo
                fi
        fi
        
        is_exit="${1:-0}"

        if [ "$is_exit" -eq 1 ]; then
                end_time="$(date +%s)"
                runtime=$((end_time-g_start_time))
                echo
                echo "Program execution lasted for $runtime seconds!"

                echo
                if [ $g_error_occurred -eq 0 ]; then
                        echo -e "${c_green}No errors have occurred during program execution!$c_normal"
                        exit 0
                else
                        echo -e "${c_red}$g_error_occurred errors have occurred during program execution!$c_normal"
                        exit 1
                fi
        fi
}

# Main function. Calls all the other functions.
function f_main {
        trap 'f_clean_trash 1' SIGINT

        g_start_time="$(date +%s)"

        f_clean_trash
        f_check_dependencies
        f_parse_flags "$@"
        f_cache_dir_check
        f_search_manga
        f_chose_manga
        f_dw_manga_index
        f_show_and_chose_chapters
        f_configure_manga_dir
        f_dw_manga
        f_fix_chapter_names
        f_clean_trash 1
}

# =========================== #
# ========== MAIN =========== #
# =========================== #

f_main "$@"
