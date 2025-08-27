FROM ubuntu:latest

# Install necessary tools for SDKMAN!
RUN apt-get update && \
    apt-get install -y curl zip unzip git nano gnupg tar wget && \
    rm -rf /var/lib/apt/lists/*

# Add the Cloud Foundry GPG key
RUN curl -fsSL https://packages.cloudfoundry.org/debian/cli.cloudfoundry.org.key | gpg --dearmor -o /usr/share/keyrings/cloudfoundry-keyring.gpg
# Add the Cloud Foundry repository
RUN echo "deb [signed-by=/usr/share/keyrings/cloudfoundry-keyring.gpg] https://packages.cloudfoundry.org/debian stable main" | tee /etc/apt/sources.list.d/cloudfoundry.list
RUN apt update && apt install --yes cf8-cli


# Install SDKMAN!
ENV SDKMAN_DIR="/usr/local/sdkman"
RUN curl -s "https://get.sdkman.io" | bash

# Add SDKMAN! to the PATH and source its initialization script
# This ensures SDKMAN! commands are available in subsequent RUN commands
RUN echo "source \"$SDKMAN_DIR/bin/sdkman-init.sh\"" >> ~/.bashrc && \
    echo "source \"$SDKMAN_DIR/bin/sdkman-init.sh\"" >> /etc/profile.d/sdkman.sh

# Example: Install a specific Java version using SDKMAN!
# The 'bash -c' is used to ensure the sourced sdkman-init.sh is active
RUN bash -c "source \"$SDKMAN_DIR/bin/sdkman-init.sh\" && sdk install java 21.0.7-oracle "

# Set the default Java version (optional)
RUN bash -c "source \"$SDKMAN_DIR/bin/sdkman-init.sh\" && sdk default java 21.0.7-oracle "

# Remove the entrypoint lines (32-37) and add this instead:
# Create a wrapper script for the sdk command
# RUN echo '#!/bin/bash' > /usr/local/bin/sdk && \
#     echo 'source "$SDKMAN_DIR/bin/sdkman-init.sh"' >> /usr/local/bin/sdk && \
#     echo 'sdk "$@"' >> /usr/local/bin/sdk && \
#     chmod +x /usr/local/bin/sdk


ENTRYPOINT ["bash -c \"source /usr/local/sdkman/bin/sdkman-init.sh\" "]


# Define the entrypoint or command for your application
# CMD ["java", "-version"]
CMD ["/bin/bash"]