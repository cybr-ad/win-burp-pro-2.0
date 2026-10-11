# ⚡ Burp Suite Pro — Universal Windows Setup

<div align="center">

[![Windows Support](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server%20(x64)-0078D6?style=for-the-badge&logo=windows&logoColor=white)](#-compatibility)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+%20%7C%207+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](burp-pro-setup.ps1)
[![Package Manager](https://img.shields.io/badge/Winget-Native%20Integration-0078D4?style=for-the-badge&logo=windows-terminal&logoColor=white)](#-features)
[![Java Runtime](https://img.shields.io/badge/Java-Oracle%20JDK%2017--26-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)](#-features)
[![License](https://img.shields.io/badge/License-MIT-purple?style=for-the-badge)](LICENSE)

**An automated, 1-click native PowerShell setup script that installs, configures, and integrates Burp Suite Professional on any modern 64-bit Windows system.**

[🚀 Quick Start](#-quick-start) • [✨ Features](#-features) • [⚙️ How It Works](#-how-it-works) • [🔑 Activation Guide](#-activation-guide) • [🖥️ How to Launch](#-how-to-launch) • [❓ Troubleshooting](#-troubleshooting)

</div>

---

## ✨ Features

- ⚡ **1-Click Automated Setup** — Sets up dependencies, installs Java, downloads Burp Suite Pro, and configures shortcuts automatically.
- 📦 **Native Winget Integration** — Downloads and silently installs Oracle JDK (17–26) using Windows Package Manager (`winget`). No manual installers or wizards required.
- 🌐 **Pure Direct Downloads** — High-speed streaming downloads using native .NET `HttpClient` with live progress bars and download speed metrics (MB/s).
- 📦 **10-Year PortSwigger Archive** — Choose proven popular releases (`2025.12.3`, `2023.3.3`, `2026.x`) or browse official releases from 2016 through 2026.
- 🤫 **Clean & Silent Launchers** — Generates both `burp.bat` and silent `burp.vbs` to eliminate annoying black command-prompt window popups.
- 🖥️ **System-Wide Windows Integration**:
  - **Global CLI Command**: Type `burp-pro` in any PowerShell, CMD, or Windows Terminal prompt.
  - **Start Menu Shortcut**: Search `Burp-pro` directly in Windows Search / Start Menu.
  - **Desktop Shortcut**: High-resolution native `.ico` desktop icon.
- 🛡️ **Clean System State** — Automatically scans and fixes stale PortSwigger `/etc/hosts` overrides and conflicting Windows Firewall block rules.

---

## 📋 Compatibility

| Component | Supported Environments |
| :--- | :--- |
| **Operating Systems** | Windows 11 (x64), Windows 10 (x64), Windows Server 2019/2022/2025 |
| **Architecture** | `x86_64` / `amd64` |
| **Shells** | Windows PowerShell 5.1 (Built-in) or PowerShell 7+ |
| **Package Manager** | Windows Package Manager (`winget`) with automatic direct fallback |
| **Java Runtimes** | Oracle JDK 17 (LTS), JDK 21 (LTS), JDK 23 *(Default & Recommended)* to JDK 26 |

---

## 🚀 Quick Start

### 1. Open PowerShell as Administrator

Press <kbd>Win</kbd> + <kbd>X</kbd> and select **Terminal (Admin)** or **Windows PowerShell (Admin)**.

### 2. Run the Installer

Navigate to your downloaded folder and run:

```powershell
# Navigate to the folder
cd "C:\path\to\burp-pro-2.0-main"

# Run the automated setup
powershell -ExecutionPolicy Bypass -File .\burp-pro-setup.ps1
```

> [!TIP]
> **Forgot to run as Admin?** No problem! The script automatically detects standard user mode and prompts you with a 1-click option to self-elevate.

---

## ⚙️ How It Works

When you run `burp-pro-setup.ps1`, the script interactively guides you through a streamlined workflow:

```text
┌────────────────────────────────────────────────────────────────────────┐
│  1. System & Network Inspection   ──> Cleans hosts & firewall conflicts │
│  2. Java Runtime Setup            ──> Silent install via winget        │
│  3. Burp Version Selection        ──> Pick 2025, 2023, 2026 or archive │
│  4. Direct JAR Downloads          ──> Native streaming download        │
│  5. Background Keygen Launch      ──> Opens GUI for offline activation │
│  6. Windows System Integration    ──> PATH, Start Menu & Desktop Icon  │
└────────────────────────────────────────────────────────────────────────┘
```

### Version Options at a Glance:

| Option | Version | Description |
| :---: | :--- | :--- |
| **1** | `v2025.12.3` | Stable, battle-tested modern release *(Default)* |
| **2** | `v2023.3.3` | Proven highest loader compatibility |
| **3** | `v2026.9.2` | Latest release with newest Burp features |
| **4** | `v2024.11.2` | Stable 2024 LTS-generation release |
| **5** | **Browse by Year** | Explore and pick from all official Pro releases (2016–2026) |
| **6** | **Custom Version** | Enter any specific version tag manually |

---

## 🔑 Activation Guide

During installation, the script launches the **burploader** Keygen window in the background. Follow these steps:

```
┌────────────────────────────────────────────────────────────────────────┐
│  1. In Keygen GUI  ──> Copy the "License" key string                   │
│  2. In Keygen GUI  ──> Click [ Run ] to launch Burp Suite Pro          │
│  3. In Burp Suite  ──> Paste the License string and click [ Next ]     │
│  4. In Burp Suite  ──> Select [ Manual Activation ]                    │
│  5. In Burp Suite  ──> Click [ Copy Request ]                          │
│  6. In Keygen GUI  ──> Paste into the "Activation Request" field       │
│  7. In Keygen GUI  ──> Copy the generated "Activation Response"        │
│  8. In Burp Suite  ──> Paste into "Activation Response" and click Next │
│  9. In Terminal    ──> Press [ Enter ] to complete setup               │
└────────────────────────────────────────────────────────────────────────┘
```

> [!NOTE]
> If you don't copy a custom loader command from Keygen, just press **Enter** in PowerShell — the script automatically calculates and configures the optimal command for you.

---

## 🖥️ How to Launch

Once setup is complete, you can start Burp Suite Pro in any of these convenient ways:

### 1. From Terminal (Anywhere)
Open PowerShell, Command Prompt, or Windows Terminal and type:
```powershell
burp-pro
```

### 2. From Windows Start Menu / Search
Press <kbd>Win</kbd>, type **Burp-pro**, and hit <kbd>Enter</kbd>.

### 3. From Desktop Shortcut
Double-click the **Burp-pro** shortcut created on your Desktop.

### 4. Direct Script Execution
Double-click `burp.vbs` (for a clean, silent start) or `burp.bat` in your Burp directory:
```
%USERPROFILE%\Documents\burp\burp.vbs
```

---

## 📁 Installed Directory Structure

The setup organizes all components cleanly in your user profile:

```
C:\Users\<YourUser>\Documents\burp\
├── burploader.jar             # Loader & keygen tool
├── burpsuite_pro_v*.jar       # Official PortSwigger Burp Suite JAR
├── burp.bat                   # Direct startup batch file
├── burp.vbs                   # Silent launcher (no console window popup)
├── burp-pro.cmd               # Global CLI command wrapper (in User PATH)
├── burpsuite.png              # Official PNG icon extracted from JAR
└── burpsuite.ico              # Multi-resolution native Windows icon

%USERPROFILE%\Desktop\Burp-pro.lnk                          # Desktop launcher
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Burp-pro.lnk # Start Menu shortcut
```

---

## ❓ Troubleshooting

<details>
<summary><b>PowerShell says: "Execution of scripts is disabled on this system"</b></summary>

Windows restricts script execution by default. Run the script using the `-ExecutionPolicy Bypass` flag:
```powershell
powershell -ExecutionPolicy Bypass -File .\burp-pro-setup.ps1
```
Or allow local scripts for your user session by running:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```
</details>

<details>
<summary><b>Winget is not recognized or not installed</b></summary>

Winget is included by default in Windows 10 (1809+) and Windows 11 via the **App Installer** package.
- If winget is missing on older Windows versions, the setup script automatically falls back to direct downloading Oracle JDK via .NET.
- You can also install or update winget from the [Microsoft Store: App Installer](https://apps.microsoft.com/detail/9nblggh4nns1).
</details>

<details>
<summary><b>A black CMD window stays open behind Burp Suite</b></summary>

The setup script creates both `burp.bat` and `burp.vbs`.
- Both the **Desktop Shortcut** and **Start Menu Shortcut** use `javaw.exe` directly, which runs Burp Suite completely windowless.
- If launching from a folder manually, double-click **`burp.vbs`** instead of `.bat` for silent background execution.
</details>

<details>
<summary><b>Keygen GUI fails to launch</b></summary>

Ensure Java is configured and supports the required flags. Test manually in PowerShell:
```powershell
java --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED -jar "$env:USERPROFILE\Documents\burp\burploader.jar"
```
</details>

<details>
<summary><b>Check or switch active Java version</b></summary>

Check your active Java version:
```powershell
java -version
```
To verify installed JDK versions in standard directories:
```powershell
Get-ChildItem "C:\Program Files\Java"
```
</details>

---

## 📜 Disclaimer & License

- **Disclaimer**: This script and repository are provided strictly for **educational and research purposes**. Burp Suite is a registered trademark of PortSwigger Ltd. Support the software authors by purchasing an official commercial license from [PortSwigger](https://portswigger.net/).
- **License**: Released under the [MIT License](LICENSE).
