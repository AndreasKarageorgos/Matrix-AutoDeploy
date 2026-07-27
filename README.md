# Matrix AutoDeploy

Automate the deployment of a private Matrix server with a single installation script.

Matrix AutoDeploy is a Bash-based installer that simplifies the deployment and configuration of a secure, self-hosted Matrix server. It is designed for enterprises, organizations, and individuals who want to quickly deploy a private Matrix instance with minimal manual configuration.

---

# Features

- 🚀 Fully automated Matrix server deployment
- 🔒 Designed for secure, private, and enterprise environments
- 🐳 Docker-based installation
- ⚙️ Automated configuration and key generation
- 🔑 Uses OpenSSL to generate passwords
- ⚡ Simple installation process
- 🛠️ Easy to maintain and customize

---

# Prerequisites

Before running the installer, update your system and install the required dependencies.

## 1. Update your system

```bash
sudo apt update
sudo apt full-upgrade -y
```

## 2. Install Docker and Git

```bash
sudo apt install docker.io git -y
```

## 3. Install Docker Compose

Depending on your Linux distribution, install **one** of the following:

```bash
sudo apt install docker-compose
```

or

```bash
sudo apt install docker-compose-v2
```

## 4. Add your user to the Docker group

```bash
sudo usermod -aG docker $USER
```

## 5. Reboot (Recommended)

To apply the Docker group changes, reboot your system:

```bash
sudo reboot
```

> **Note**
>
> Instead of rebooting, you can simply log out and log back in.

---

# OpenSSL

This installer uses **OpenSSL** to generate passwords during the installation process.

OpenSSL is included by default on most Debian and Ubuntu-based distributions. If it is not available on your system, install it using:

```bash
sudo apt install openssl
```

---

# Installation

Clone the repository:

```bash
git clone https://github.com/AndreasKarageorgos/Matrix-AutoDeploy.git
```

Navigate into the project directory:

```bash
cd Matrix-AutoDeploy
```

Run the installer:

```bash
sudo ./install.sh
```

---

# SSL/TLS Configuration

> **Important:** Matrix AutoDeploy **does not** configure HTTPS (port **443**) or obtain SSL/TLS certificates.

This is **intentional**.

There are many valid ways to securely expose a Matrix server, including:

- Nginx reverse proxy
- Apache2 reverse proxy
- Cloudflare Tunnel
- HAProxy
- Caddy
- Existing enterprise reverse proxy or load balancer infrastructure

Rather than forcing a specific web server or SSL configuration, Matrix AutoDeploy leaves these choices to the administrator. This allows you to integrate the Matrix server into your existing infrastructure without being locked into a particular setup.

## Additional Steps Required

After the installation completes, you must:

1. Configure a reverse proxy or another method to expose the Matrix server over HTTPS.
2. Obtain and install a valid SSL/TLS certificate (for example, Let's Encrypt).
3. Forward HTTPS traffic (port **443**) to your Matrix server.
4. Verify that your homeserver is accessible via HTTPS before allowing clients to connect.

> **Note**
>
> Matrix clients and server federation require a correctly configured HTTPS endpoint. Your server will **not** be ready for production until SSL/TLS has been configured.

---

# Requirements

- Ubuntu/Debian-based Linux distribution
- Docker Engine
- Docker Compose
- Git
- OpenSSL (pre-installed on most Debian/Ubuntu systems)
- Root or sudo privileges

---

# What the Installer Does

The installer automates the deployment of a private Matrix server by:

- Installing and configuring the required services
- Generating secure passwords using OpenSSL
- Deploying the Matrix server using Docker
- Creating the necessary configuration files
- Preparing the Matrix server for production deployment

The installer **does not**:

- Configure HTTPS (SSL/TLS)
- Install or configure a reverse proxy
- Obtain SSL certificates
- Configure DNS records

These steps are intentionally left to the administrator to allow maximum flexibility.

---

# Contributing

Contributions, bug reports, and feature requests are welcome.

If you have an idea for an improvement or discover a bug, feel free to open an issue or submit a pull request.

---

# Disclaimer

This project automates the deployment of a Matrix server but does not replace proper system administration.

Before using this installer in a production environment, you should:

- Review the installation script.
- Configure HTTPS using your preferred method.
- Secure your server according to your organization's policies.
- Keep your operating system and Docker installation up to date.
- Configure backups and monitoring.

---

# License

This project is licensed under the MIT License.