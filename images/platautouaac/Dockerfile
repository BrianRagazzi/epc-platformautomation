
FROM platform-automation:5.3.0

RUN apt-get -y update && \
    apt-get install -y wget jq build-essential ruby-full curl sshpass && \
    gem install cf-uaac && \
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq 
# Add the Cloud Foundry GPG key
RUN curl -fsSL https://packages.cloudfoundry.org/debian/cli.cloudfoundry.org.key | gpg --dearmor -o /usr/share/keyrings/cloudfoundry-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudfoundry-keyring.gpg] https://packages.cloudfoundry.org/debian stable main" | tee /etc/apt/sources.list.d/cloudfoundry.list
RUN apt update && apt install --yes cf8-cli && \
    gem install cf-uaac && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV PATH="/rootfs/var/lib/gems/3.0.0/bin:${PATH}"

