# Images for Platform Automation

## Import the original Platform Automation image:
```
docker import vsphere-platform-automation-image-5.3.0.tar.gz platform-automation:5.3.0
```

# Platform Automation with UAAC (and om and cf)

## Build custom image for Platform Automation with UAAC:
```
cd platautouaac
docker build -t platauto-uaac:5.3.0 -f Dockerfile .
```

### test
```
docker run --name "test" platauto-uaac:5.3.0 uaac version && cf version && om version
docker rm test
```

## Export custom image to tar.gz:
```
docker export $(docker create platauto-uaac:5.3.0 uaac version) | gzip > platauto-uaac-5.3.0.tar.gz
```


# Platform Automation Java, NodeJS, Maven

## Build custom image for Platform Automation to build apps:
```
cd builder
docker build -t platauto-builder:5.3.0 -f Dockerfile .
```

### test
```
docker run --name "testbuilder" platauto-builder:5.3.0 sdk current
docker rm testbuilder
```

## Export custom image to tar.gz:
```
docker export $(docker create platauto-builder:5.3.0 sdk current) | gzip > platauto-builder-5.3.0.tar.gz
```
