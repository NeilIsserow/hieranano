***NB! We have not provided any security/https/encryption in this code. We use your pem keys that you provide. Be sure to note this and if you wish to secure the app with https! In addition we have made extensive use of AI to create this app, and as a ersult your use of this app is provided asi-is with no warranty implied or otherwise from the author or the authors current organization!***

**Please note Consult AI feature is not yet active!**

# HieraNano

HieraNano is a high-performance, minimalist architecture assistant built specifically for Puppet Enterprise to provide a simpoly way to work wioth Hiera and eyaml in your Puppet Enterprise environment. It is specifically built for teams as well as environments as a python/flask web app. All source code is provided for you to inspect and update to your requirements or even just use as a template to make it much better.

---


## Installation & Deployment

HieraNano uses a master deployment layer script to configure its directory layout, SQLite schema, and WSGI execution engine.

### 1. Provision Virtual Environment and Directory Roots
Run the automated deployment helper script or configure your environment manually:
```bash
# Ensure dependencies are present
sudo apt-get update && sudo apt-get install -y python3-pip python3-venv sqlite3 lsof

# Verify the app path layout matches your service configurations
mkdir -p /root/.hieranano
cd /root/.hieranano
python3 -m venv venv
./venv/bin/pip install flask requests gunicorn
