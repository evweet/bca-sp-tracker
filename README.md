
# Setup

## Under Linux directly

### 1. Clone the repository

```bash
git clone https://github.com/evweet/bca-sp-tracker.git
```

### 2. Configure the tracker

```bash
cd <project-directory>

### 1. Modify the sp-tracker.conf file

### 2. Add the database connection credentials to the secret.pgpass file
```

### 3. Set up first commit

```bash
### Remove the existing .git directory
rm -rf .git

### Add execution permission to the setup script
chmod +x src/*.sh

### Run the setup script
./src/setup.sh
```

## Under Docker