# epc-platformautomation

# Using the `add_pipelines.ps1` Script

The `add_pipelines.ps1` PowerShell script automates the process of adding pipeline files to your Concourse configuration.
**Important:** You must run this script from the root of the repository using the following command:

```
./scripts/add_pipelines.ps1
```

Running the script from the root ensures that all relative paths referenced within the script work correctly. This will allow the script to locate and process pipeline files as intended.

 
## These pipelines are used in EPC TPCF v2 environments to give operators options to install and configure TPCF components

# To Do:
* Document how to make sure concourse is running
* scripts to update and add pipelines to concourse
* Diagram of the configuration


## Pipeline Features:
* Add Yannick's Chat App
* Enable TIA
* configure Hub Collector


