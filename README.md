# epc-platformautomation

# Using the `add_pipelines.ps1` Script

The `add_pipelines.ps1` PowerShell script automates the process of adding pipeline files to your Concourse configuration.
**Important:** You must run this script from the root of the repository using the following command:

```
./scripts/add_pipelines.ps1
```

Running the script from the root ensures that all relative paths referenced within the script work correctly. This will allow the script to locate and process pipeline files as intended.

## Pipeline Descriptions

Below are brief descriptions of the main pipelines in this repository (excluding those under `archive` and `testing`):

### `pipeline-end2end.yml`
This is the primary end-to-end automation pipeline for deploying and configuring the TPCF platform and its components.  
It orchestrates the following:
- Ops Manager VM creation and configuration
- BOSH Director and stemcell setup
- Upload, stage, and configure products such as SRT, GenAI, Postgres, Hub, and Hub Collector
- Certificate generation and injection into product configurations
- Post-install tasks, such as adding LDAP users and configuring orgs/spaces
- Resource cleanup and cache management
- Integration and update jobs for Hub Collector and CF
- Teardown and cleanup of the environment

### `pipeline-foundation.yml`
This pipeline is focused on foundational setup tasks for the TPCF platform.  
It typically includes:
- Initial environment preparation
- Core infrastructure provisioning
- Uploading and configuring base products required for the foundation

> **Note:** For more details on each pipeline, review the corresponding YAML files in the `pipelines/` directory.

## These pipelines are used in EPC TPCF v2 environments to give operators options to install and configure TPCF components

# To Do:
* Document how to make sure concourse is running
* scripts to update and add pipelines to concourse
* Diagram of the configuration
* consider adding pipelines to teams for grouping:  fly -t ci set-team -n end-2-end /local-user:admin /non-interactive

## Pipeline Features:
* Add Yannick's Chat App
* Enable TIA
* configure Hub Collector


