![Total Visitors](https://komarev.com/ghpvc/?username=aron-666-pcdn&color=green)

# Titan-PCDN Service Management Script

---

<div align="center">
  
### ⚠️ **Important Notice** ⚠️

</div>

> ### 💡 **This service requires being added to a whitelist to use**
> 
> Register with the invitation code <code>LzA0HD</code> and then contact 包包 to obtain whitelist access.
> 
> [Register Now](https://test4.titannet.io/Invitelogin?code=LzA0HD)
> 
> <table>
> <tr>
> <td width="100"><b>👤 Contact:</b></td>
> <td><b>包包</b></td>
> </tr>
> <tr>
> <td><b>💬 WeChat:</b></td>
> <td><code>baobao11bd</code></td>
> </tr>
> <tr>
> <td><b>📱 Telegram:</b></td>
> <td><a href="https://t.me/bdbaobao">@bdbaobao</a></td>
> </tr>
> </table>
---

> ## 🚀 **Our Solution vs Official Tutorial**
> 
> | Comparison Item | Official Tutorial | Our Solution |
> |---------|---------|--------------|
> | **Network Connection** | ❌ NAT3/NAT4 type, low earnings | ✅ NAT1/Public network connection, higher earnings (router requires additional configuration) |
> | **VPS Support** | ❌ The official tutorial for China region cannot run on VPS | ✅ Perfect support for VPS environments |
> | **Deployment Complexity** | ❌ Cumbersome steps, manual configuration required for multiple settings | ✅ **One-click deployment**, time-saving and efficient |
> | **Daemon Process** | ❌ No daemon process, manual restart required after disconnection | ✅ Built-in daemon process, automatic recovery |
> | **Earnings Effect** | ❌ Basic earnings | ✅ Improved network quality, **earnings can reach up to 2-3 times higher!** (router requires additional configuration)|

---

## System Requirements

- Linux operating system (Ubuntu, Debian, CentOS, RHEL, Fedora, etc.)
- Root privileges
- Network connection

---

## All Commands Overview

```bash
./pcdn.sh [command] [options]
```

Basic commands:
- `start`: Start PCDN service
- `stop`: Stop PCDN service
- `delete`: Delete PCDN service and data
- `config`: Configure PCDN service
- `logs`: View Docker container logs
- `agent-logs`: View PCDN agent logs

Global options:
- `-i, --install [cn]`: Automatically install Docker environment
  - Without parameter: Use international source
  - With `cn` parameter: Use Chinese source

---

## Quick Start

### Basic Installation and Startup

#### Other Regions Installation

```bash
# 1. Download the script and set permissions (International region uses GitHub source, only need to download once)
git clone https://github.com/aron-666/Titan-PCDN-EN.git titan-pcdn
cd titan-pcdn
chmod +x pcdn.sh

# 2. Start the service (will enter interactive configuration)
sudo ./pcdn.sh start
```

#### China Region Installation

```bash
# 1. Download the script and set permissions (China region uses Gitee source, only need to download once)
git clone https://gitee.com/hiro199/Titan-PCDN.git titan-pcdn
cd titan-pcdn
chmod +x pcdn.sh

# 2. Start the service (will enter interactive configuration)
sudo ./pcdn.sh start
```

### Quick Deployment (One-Click Start)

#### Other Regions Deployment

```bash
# 1. Download the script and set permissions (International region uses GitHub source, only need to download once)
git clone https://github.com/aron-666/Titan-PCDN-EN.git titan-pcdn
cd titan-pcdn
chmod +x pcdn.sh

# 2. Other regions quick start
sudo ./pcdn.sh start -t your_TOKEN -i
```

#### China Region Deployment

```bash
# 1. Download the script and set permissions (China region uses Gitee source, only need to download once)
git clone https://gitee.com/hiro199/Titan-PCDN.git titan-pcdn
cd titan-pcdn
chmod +x pcdn.sh

# 2. China region quick start
sudo ./pcdn.sh start -t your_TOKEN -r cn -i cn
```

> Note: The `-r` parameter is optional, used to specify region. When set to `cn`, special processing for China region will be performed.
> The `-i cn` parameter is used to install Docker using Chinese mirror sources in China region.

---

## Command Details

### Start PCDN Service

```bash
sudo ./pcdn.sh start [options]
```

Options:
- `-t, --token TOKEN`: Specify token
- `-r, --region REGION`: Specify region (when set to `cn`, special processing for China region will be performed)

Examples:
```bash
# Other regions
sudo ./pcdn.sh start -t your_token_here

# China region
sudo ./pcdn.sh start -t your_token_here -r cn
```

### Configure PCDN Service

```bash
sudo ./pcdn.sh config [options]
```

Options:
- `-t, --token TOKEN`: Set token
- `-r, --region REGION`: Set region (when set to `cn`, special processing for China region will be performed)

Examples:
```bash
# Other regions
sudo ./pcdn.sh config -t your_token_here

# China region
sudo ./pcdn.sh config -t your_token_here -r cn
```

### Stop PCDN Service

```bash
sudo ./pcdn.sh stop
```

### Delete PCDN Service

```bash
sudo ./pcdn.sh delete
```

### View Docker Container Logs

```bash
sudo ./pcdn.sh logs
```
This command displays the latest 100 log entries of the Docker container and updates in real time. You can exit by pressing Ctrl+C.

### View PCDN Agent Logs

```bash
sudo ./pcdn.sh agent-logs
```
This command displays the latest 100 log entries of the PCDN agent and updates in real time. You can exit by pressing Ctrl+C.

### Interactive Menu

Running the script without parameters will display an interactive menu:

```bash
sudo ./pcdn.sh
```

## Configuration Files

The script generates the following configuration files in the `conf` directory:

- `.env`: Contains HOOK_ENABLE and HOOK_REGION settings
- `.key`: Contains the authorization token

## System Optimization

The script automatically adjusts system limits to optimize PCDN service performance:

- Sets file descriptor limit (524288)
- Adjusts system parameters:
  - fs.inotify.max_user_instances = 25535
  - net.core.rmem_max=600000000
  - net.core.wmem_max=600000000

## Troubleshooting

### Docker Related Issues

- If Docker installation fails, try running the script again with the `-i` parameter
- If in mainland China, use the `-i cn` parameter to use Chinese mirror sources

### Log Viewing Issues

- If you cannot see logs, please confirm the service has started
- Newly installed services may take a few minutes to generate logs
- Using the `logs` command to view Docker container logs can help diagnose startup issues

### Configuration Issues

- If the service fails to start, check that configuration files are generated correctly
- Use the `./pcdn.sh config` command to reconfigure the service

## Notes

- This script requires root privileges to run
- Changes to system limit settings may require re-login or system restart to fully take effect
