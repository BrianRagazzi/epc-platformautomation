#!/bin/bash

parse_yaml_config() {
  local source_file="$1"
  local placeholder_file="placeholders.yml"
  local defaults_file="defaults.yml"
  local temp_file="temp_paths.txt"
  # Check if source file exists
  if [ ! -f "$source_file" ]; then
      echo "Error: Source file '$source_file' not found."
      return 1
  fi

  # Check if yq is installed
  if ! command -v yq &> /dev/null; then
      echo "Error: This script requires yq to be installed."
      echo "Please install it using one of the following methods:"
      echo "  - wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"
      echo "  - snap install yq"
      echo "  - brew install yq (on macOS)"
      return 1
  fi

  # Get yq version
  YQ_VERSION=$(yq --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
  YQ_MAJOR_VERSION=$(echo $YQ_VERSION | cut -d. -f1)

  # Check if yq version is 4 or higher (syntax differs between v3 and v4+)
  if [ "$YQ_MAJOR_VERSION" -lt 4 ]; then
      echo "Error: This script requires yq version 4.0.0 or higher."
      echo "Your version: $YQ_VERSION"
      return 1
  fi

  echo "Creating placeholder file: $placeholder_file"
  # First, copy the source file to the placeholder file
  cp "$source_file" "$placeholder_file"

  # Create an empty defaults file
  echo "# Default values extracted from $source_file" > "$defaults_file"

  # Define the top-level sections to process
  sections=("product-properties" "network-properties" "resource-config" "errand-config")

  # Process each top-level section
  for section in "${sections[@]}"; do
      echo "Processing $section section..."

      # Check if the section exists in the source file
      if ! yq eval "has(\"$section\")" "$source_file" | grep -q "true"; then
          echo "  Section $section not found in source file, skipping."
          continue
      fi

      # Process based on the section type
      case "$section" in
          "product-properties")
              # For product-properties, directly get all keys since they may contain dots
              keys=$(yq eval ".$section | keys | .[]" "$source_file")

              # Process each key
              for key in $keys; do
                  # Skip if the key doesn't have a value field
                  if ! yq eval ".$section.\"$key\".value | type" "$source_file" &>/dev/null; then
                      continue
                  fi

                  # Get the value type
                  value_type=$(yq eval ".$section.\"$key\".value | type" "$source_file")

                  # Create placeholder key by removing leading dot and replacing dots with slashes
                  base_placeholder_key=$(echo "$key" | sed 's/^\.//' | sed 's/\./\//g')

                  # Handle different types of values
                  if [[ "$value_type" == "!!seq" ]]; then
                      # Process arrays that might contain certificates
                      items_count=$(yq eval ".$section.\"$key\".value | length" "$source_file")
                      has_certificates=false

                      # Check if this is an array of certificate objects
                      for ((i=0; i<items_count; i++)); do
                          if yq eval ".$section.\"$key\".value[$i] | has(\"certificate\")" "$source_file" | grep -q "true"; then
                              has_certificates=true

                              # Process certificate name if it exists
                              if yq eval ".$section.\"$key\".value[$i].certificate | has(\"name\")" "$source_file" | grep -q "true"; then
                                  name_value=$(yq eval ".$section.\"$key\".value[$i].certificate.name" "$source_file")
                                  name_placeholder_key="${base_placeholder_key}_${i}_name"

                                  # Skip if value already contains a placeholder
                                  if [[ "$name_value" != *"(("*"))"* ]]; then
                                      yq eval ".$section.\"$key\".value[$i].certificate.name = \"(($name_placeholder_key))\"" -i "$placeholder_file"
                                      echo "$name_placeholder_key: $name_value" >> "$defaults_file"
                                  fi
                              fi

                              # Process certificate
                              if yq eval ".$section.\"$key\".value[$i].certificate | has(\"cert_pem\")" "$source_file" | grep -q "true"; then
                                  cert_value=$(yq eval ".$section.\"$key\".value[$i].certificate.cert_pem" "$source_file")
                                  cert_placeholder_key="${base_placeholder_key}_${i}_cert_pem"

                                  # Skip if value already contains a placeholder
                                  if [[ "$cert_value" != *"(("*"))"* ]]; then
                                      # Use a simple string replacement for the placeholder
                                      yq eval ".$section.\"$key\".value[$i].certificate.cert_pem = \"(($cert_placeholder_key))\"" -i "$placeholder_file"

                                      # Write certificate to defaults file with proper formatting
                                      echo "$cert_placeholder_key: |-" >> "$defaults_file"
                                      echo "$cert_value" | sed 's/^/  /' >> "$defaults_file"
                                  fi
                              fi

                              # Process private key
                              if yq eval ".$section.\"$key\".value[$i].certificate | has(\"private_key_pem\")" "$source_file" | grep -q "true"; then
                                  key_value=$(yq eval ".$section.\"$key\".value[$i].certificate.private_key_pem" "$source_file")
                                  key_placeholder_key="${base_placeholder_key}_${i}_private_key_pem"

                                  # Skip if value already contains a placeholder
                                  if [[ "$key_value" != *"(("*"))"* ]]; then
                                      # Use a simple string replacement for the placeholder
                                      yq eval ".$section.\"$key\".value[$i].certificate.private_key_pem = \"(($key_placeholder_key))\"" -i "$placeholder_file"

                                      # Write key to defaults file with proper formatting
                                      echo "$key_placeholder_key: |-" >> "$defaults_file"
                                      echo "$key_value" | sed 's/^/  /' >> "$defaults_file"
                                  fi
                              fi
                          fi
                      done

                      # Skip if we processed certificates
                      if $has_certificates; then
                          continue
                      fi

                      # Skip other arrays
                      continue
                  elif [[ "$value_type" == "!!map" ]]; then
                      # Check if this is a certificate structure
                      if yq eval ".$section.\"$key\".value | has(\"cert_pem\")" "$source_file" | grep -q "true"; then
                          # Process cert_pem
                          cert_value=$(yq eval ".$section.\"$key\".value.cert_pem" "$source_file")
                          cert_placeholder_key="${base_placeholder_key}_cert_pem"

                          # Skip if value already contains a placeholder
                          if [[ "$cert_value" != *"(("*"))"* ]]; then
                              # Use a simple string replacement for the placeholder
                              yq eval ".$section.\"$key\".value.cert_pem = \"(($cert_placeholder_key))\"" -i "$placeholder_file"

                              # Write certificate to defaults file with proper formatting
                              echo "$cert_placeholder_key: |-" >> "$defaults_file"
                              echo "$cert_value" | sed 's/^/  /' >> "$defaults_file"
                          fi
                      fi

                      if yq eval ".$section.\"$key\".value | has(\"private_key_pem\")" "$source_file" | grep -q "true"; then
                          # Process private_key_pem
                          key_value=$(yq eval ".$section.\"$key\".value.private_key_pem" "$source_file")
                          key_placeholder_key="${base_placeholder_key}_private_key_pem"

                          # Skip if value already contains a placeholder
                          if [[ "$key_value" != *"(("*"))"* ]]; then
                              # Use a simple string replacement for the placeholder
                              yq eval ".$section.\"$key\".value.private_key_pem = \"(($key_placeholder_key))\"" -i "$placeholder_file"

                              # Write key to defaults file with proper formatting
                              echo "$key_placeholder_key: |-" >> "$defaults_file"
                              echo "$key_value" | sed 's/^/  /' >> "$defaults_file"
                          fi
                      fi

                      # Skip other complex types
                      continue
                  fi

                  # For simple values (non-map, non-array)
                  # Get the value
                  value=$(yq eval ".$section.\"$key\".value" "$source_file")

                  # Skip if value already contains a placeholder (double parentheses)
                  if [[ "$value" == *"(("*"))"* ]]; then
                      continue
                  fi

                  # Skip certain patterns that shouldn't be parameterized
                  if [[ "$key" == *"credentials"* || "$key" == *"password"* || "$key" == *"secret"* ]]; then
                      continue
                  fi

                  placeholder_key="$base_placeholder_key"

                  # Update the placeholder file with the placeholder
                  yq eval ".$section.\"$key\".value = \"(($placeholder_key))\"" -i "$placeholder_file"

                  # Add the default value to the defaults file
                  if [[ "$value" == *$'\n'* ]]; then
                      # Multi-line string
                      echo "$placeholder_key: |-" >> "$defaults_file"
                      echo "$value" | sed 's/^/  /' >> "$defaults_file"
                  else
                      # Single-line value
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi
              done
              ;;

          "network-properties")
              # For network-properties, handle its specific structure
              # Process network name
              if yq eval ".$section.network.name | type" "$source_file" | grep -q -v "!!null"; then
                  value=$(yq eval ".$section.network.name" "$source_file")
                  placeholder_key="$section/network/name"
                  yq eval ".$section.network.name = \"(($placeholder_key))\"" -i "$placeholder_file"
                  echo "$placeholder_key: $value" >> "$defaults_file"
              fi

              # Process singleton_availability_zone
              if yq eval ".$section.singleton_availability_zone.name | type" "$source_file" | grep -q -v "!!null"; then
                  value=$(yq eval ".$section.singleton_availability_zone.name" "$source_file")
                  placeholder_key="$section/singleton_availability_zone/name"
                  yq eval ".$section.singleton_availability_zone.name = \"(($placeholder_key))\"" -i "$placeholder_file"
                  echo "$placeholder_key: $value" >> "$defaults_file"
              fi

              # Process other_availability_zones (array of objects)
              az_count=$(yq eval ".$section.other_availability_zones | length" "$source_file")
              for ((i=0; i<az_count; i++)); do
                  if yq eval ".$section.other_availability_zones[$i].name | type" "$source_file" | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.other_availability_zones[$i].name" "$source_file")
                      placeholder_key="$section/other_availability_zones_$i/name"
                      yq eval ".$section.other_availability_zones[$i].name = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi
              done
              ;;

          "resource-config")
              # For resource-config, process each resource type
              resource_types=$(yq eval ".$section | keys | .[]" "$source_file")

              for resource_type in $resource_types; do
                  # Process instances - include "automatic" values
                  if yq eval ".$section.\"$resource_type\".instances | type" "$source_file" | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".instances" "$source_file")
                      placeholder_key="$section/$resource_type/instances"
                      yq eval ".$section.\"$resource_type\".instances = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi

                  # Process max_in_flight
                  if yq eval ".$section.\"$resource_type\".max_in_flight | type" "$source_file" | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".max_in_flight" "$source_file")
                      placeholder_key="$section/$resource_type/max_in_flight"
                      yq eval ".$section.\"$resource_type\".max_in_flight = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi

                  # Process persistent_disk.size_mb - include "automatic" values
                  if yq eval ".$section.\"$resource_type\".persistent_disk.size_mb | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".persistent_disk.size_mb" "$source_file")
                      placeholder_key="$section/$resource_type/persistent_disk_size_mb"
                      yq eval ".$section.\"$resource_type\".persistent_disk.size_mb = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi

                  # Process persistent_disk.name - include "automatic" values
                  if yq eval ".$section.\"$resource_type\".persistent_disk.name | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".persistent_disk.name" "$source_file")
                      placeholder_key="$section/$resource_type/persistent_disk_name"
                      yq eval ".$section.\"$resource_type\".persistent_disk.name = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi

                  # Process instance_type.id - include "automatic" values
                  if yq eval ".$section.\"$resource_type\".instance_type.id | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".instance_type.id" "$source_file")
                      placeholder_key="$section/$resource_type/instance_type_id"
                      yq eval ".$section.\"$resource_type\".instance_type.id = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi

                  # Process swap_as_percent_of_memory_size - include "automatic" values
                  if yq eval ".$section.\"$resource_type\".swap_as_percent_of_memory_size | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".swap_as_percent_of_memory_size" "$source_file")
                      placeholder_key="$section/$resource_type/swap_as_percent_of_memory_size"
                      yq eval ".$section.\"$resource_type\".swap_as_percent_of_memory_size = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi

                  # Process nsxt.lb.server_pools array if it exists
                  if yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools | type" "$source_file" 2>/dev/null | grep -q "!!seq"; then
                      # Get the number of server pools
                      pools_count=$(yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools | length" "$source_file")

                      for ((i=0; i<pools_count; i++)); do
                          # Process server pool name
                          if yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools[$i].name | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                              value=$(yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools[$i].name" "$source_file")
                              placeholder_key="$section/$resource_type/nsxt_lb_server_pools_${i}_name"
                              yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools[$i].name = \"(($placeholder_key))\"" -i "$placeholder_file"
                              echo "$placeholder_key: $value" >> "$defaults_file"
                          fi

                          # Process server pool port
                          if yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools[$i].port | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                              value=$(yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools[$i].port" "$source_file")
                              placeholder_key="$section/$resource_type/nsxt_lb_server_pools_${i}_port"
                              yq eval ".$section.\"$resource_type\".nsxt.lb.server_pools[$i].port = \"(($placeholder_key))\"" -i "$placeholder_file"
                              echo "$placeholder_key: $value" >> "$defaults_file"
                          fi
                      done
                  fi

                  # Process nsxt.ns_groups array if it exists
                  if yq eval ".$section.\"$resource_type\".nsxt.ns_groups | type" "$source_file" 2>/dev/null | grep -q "!!seq"; then
                      # Get the number of ns_groups
                      groups_count=$(yq eval ".$section.\"$resource_type\".nsxt.ns_groups | length" "$source_file")

                      for ((i=0; i<groups_count; i++)); do
                          # Process ns_group name
                          if yq eval ".$section.\"$resource_type\".nsxt.ns_groups[$i] | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                              value=$(yq eval ".$section.\"$resource_type\".nsxt.ns_groups[$i]" "$source_file")
                              placeholder_key="$section/$resource_type/nsxt_ns_groups_${i}"
                              yq eval ".$section.\"$resource_type\".nsxt.ns_groups[$i] = \"(($placeholder_key))\"" -i "$placeholder_file"
                              echo "$placeholder_key: $value" >> "$defaults_file"
                          fi
                      done
                  fi

                  # Process nsxt.vif_type if it exists
                  if yq eval ".$section.\"$resource_type\".nsxt.vif_type | type" "$source_file" 2>/dev/null | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$resource_type\".nsxt.vif_type" "$source_file")
                      placeholder_key="$section/$resource_type/nsxt_vif_type"
                      yq eval ".$section.\"$resource_type\".nsxt.vif_type = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi
              done
              ;;

          "errand-config")
              # For errand-config, process each errand
              errands=$(yq eval ".$section | keys | .[]" "$source_file")

              for errand in $errands; do
                  # Process post-deploy-state
                  if yq eval ".$section.\"$errand\".post-deploy-state | type" "$source_file" | grep -q -v "!!null"; then
                      value=$(yq eval ".$section.\"$errand\".post-deploy-state" "$source_file")
                      value_type=$(yq eval ".$section.\"$errand\".post-deploy-state | type" "$source_file")
                      placeholder_key="$section/$errand/post-deploy-state"
                      yq eval ".$section.\"$errand\".post-deploy-state = \"(($placeholder_key))\"" -i "$placeholder_file"
                      echo "$placeholder_key: $value" >> "$defaults_file"
                  fi
              done
              ;;
      esac

  done

  # Clean up temp file
  rm -f "$temp_file"

  # Sort the defaults file
  #sort "$defaults_file" -o "$defaults_file"

  echo "Completed successfully!"
  echo "Created $placeholder_file and $defaults_file"
}



if [ $# -ne 1 ]; then
  echo "Usage: $0 <source_yaml_file>"
  exit 1
fi

parse_yaml_config "$1"
