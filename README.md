# push to packagecloud

```yaml
    - name: push to packagecloud
      uses: emqx/push-to-packagecloud@main
      env:
        GIT_TOKEN: ${{ secrets.GIT_TOKEN }}
        PACKAGECLOUD_TOKEN: ${{ secrets.PACKAGECLOUD_TOKEN }}
      with:
        product: emqx
        version: 5.0.0
```
