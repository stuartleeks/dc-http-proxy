# dc-http-proxy

Repo to simplify setting up an environment for testing VS Code Dev containers behind an HTTP Proxy


## Setup

1. Clone this repo
2. Open the repo in VS Code as a dev container
3. Run `az login` in the terminal to sign in to your Azure Subscription (run `az account set` to set the right subscription if you have multiple)
4. Copy `sample.env` to `.env` and fill in the values
5. Run `./scripts/deploy.sh` to deploy the resources to Azure

This will deploy the following resources to Azure:
- VNET with 2 subnets (`proxy` and `default`). The `proxy` subnet is allowed outbound HTTP access but the `default` subnet is not (traffic must be routed via the `proxy` subnet)
- Linux VM in the `proxy` subnet, configured with the squid proxy
- Windows VM in the `default` subnet

The final step of the setup is to configure the Windows VM:
- set the proxy server to the squid proxy
  - From the Windows Start menu, search for "Proxy Settings"
  - Click "Edit" next to "Use setup script"
  - Paste "http://10.0.1.4/proxy-config.pac" into the "Script address" field and click "Save"
- install any apps (e.g. Visual Studio Code)


