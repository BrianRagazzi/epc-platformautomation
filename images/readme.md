# Images for Platform Automation

## Import the original:
```
docker import vsphere-platform-automation-image-5.3.0.tar.gz platform-automation:5.3.0
```


# Build custom image:
```
docker build -t platauto-uaac:5.3.0 -f Dockerfile .
```

## test
```
docker run --name "test" platauto-uaac:5.3.0 uaac version && cf version && om version
docker rm test
```

# Export custom image to tar.gz:
```
docker export $(docker create platauto-uaac:5.3.0 uaac version) | gzip > platauto-uaac-5.3.0.tar.gz
```

## Multi-step option:
### Create a container from the image (without running it)
```
docker create --name temp_container platauto-uaac:5.3.0 uaac version
```

### Export the container's filesystem
```
docker export temp_container | gzip > platautouaac/platauto-uaac-5.3.0.tar.gz
```

### Clean up the temporary container
```
docker rm temp_container
```