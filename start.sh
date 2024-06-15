#!/usr/bin/env bash

# Function to print colored messages
print_color() {
    color=$1
    shift
    echo -e "\033[${color}m$@\033[0m"
}

# Function to check if jq is installed, and install it if not
check_install_jq() {
    if ! command -v jq &> /dev/null; then
        print_color "33" "jq is not installed. Installing jq..."
        # Check the package manager and install jq
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update
            sudo apt-get install -y jq
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y jq
        elif [ -x "$(command -v brew)" ]; then
            brew install jq
        else
            print_color "31" "Package manager not found. Please install jq manually."
            exit 1
        fi
    fi
}

# Check and install jq if necessary
check_install_jq

print_color "32" "Please enter registry user: "
read user

print_color "32" "Please enter registry password: "
read -s password

print_color "32" "Please enter registry address (e.g. https://myregistrydomain.com): "
read url

# Fetch the list of repositories (images)
response=$(curl -u "$user:$password" "$url/v2/_catalog" 2>/dev/null)

# Check if the curl command was successful
if [ $? -eq 0 ]; then
    # Extract the repository names
    repos=$(echo "$response" | jq -r '.repositories[]')
    
    if [ -z "$repos" ]; then
        print_color "31" "No repositories found."
        exit 1
    fi

    while true; do
        # Display the menu and let the user select an image
        PS3=$(print_color "34" "Please enter the number corresponding to the image name (or type 'exit' to quit): ")
        select imageName in $repos; do
            if [ "$REPLY" == "exit" ]; then
                print_color "32" "Exiting..."
                exit 0
            elif [ -n "$imageName" ]; then
                print_color "32" "You have selected: $imageName"
                response=$(curl -u "$user:$password" "$url/v2/$imageName/tags/list" 2>/dev/null)
                # Check if the curl command was successful
                if [ $? -eq 0 ]; then
                    # Extract the tag names
                    tags=$(echo "$response" | jq -r '.tags[]')
                    
                    if [ -z "$tags" ]; then
                        print_color "31" "No tags found."
                    else
                        # Display the menu and let the user select a tag
                        PS3=$(print_color "34" "Please enter the number corresponding to the tag (or type 'back' to select another image): ")
                         
                        select tag in $tags; do
                            if [ "$REPLY" == "back" ]; then
                                break
                            elif [ -n "$tag" ]; then
                                print_color "32" "You have selected: $tag"
                                # Get the manifest to retrieve the digest
                                manifestResponse=$(curl -u "$user:$password" -s -D - -o /dev/null "$url/v2/$imageName/manifests/$tag" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json')
                                if [ $? -eq 0 ]; then
                                    digest=$(echo "$manifestResponse" | grep -i Docker-Content-Digest | awk '{print $2}' | tr -d '\r')
                                    if [ -n "$digest" ]; then
                                        print_color "32" "Digest for $imageName:$tag is $digest"
                                        
                                        # Ask user if they want to delete the image
                                        print_color "33" "Do you want to delete this image? (y/n): "
                                        read confirmDelete
                                        
                                        if [ "$confirmDelete" == "y" ]; then
                                            # Delete the image by digest
                                            deleteResponse=$(curl -u "$user:$password" -X DELETE "$url/v2/$imageName/manifests/$digest" 2>/dev/null)
                                            if [ $? -eq 0 ]; then
                                                print_color "32" "Image $imageName:$tag with digest $digest has been deleted successfully."
                                            else
                                                print_color "31" "Failed to delete the image $imageName:$tag."
                                            fi
                                        else
                                            print_color "32" "Image deletion aborted."
                                        fi
                                    else
                                        print_color "31" "Unable to extract the digest."
                                    fi
                                else
                                    print_color "31" "Unable to get the manifest for the selected tag."
                                fi
                                break
                            else
                                print_color "31" "Invalid selection. Please try again."
                            fi
                        done
                    fi
                else
                    print_color "31" "Unable to get the tags list for the selected repository."
                fi
                break
            else
                print_color "31" "Invalid selection. Please try again."
            fi
        done
    done
else
    print_color "31" "Unable to get the list of repositories."
    exit 1
fi
