# Guide for publication

1. Create a branch with the name of the version `x.x.x`

2. If Reach5 has been upgraded to a new major version, update the version range in [Package.swift](Package.swift) <br>
Update to latest package versions of dependencies for SPM in XCode or with this command
    ```shell
    swift package update
    ```

3. Update the [CHANGELOG.md](CHANGELOG.md) file

4. Test the modifications on the SPM project DemoSharedCredentials.

5. Submit and merge the pull request

6. Add git tag `x.x.x` to the merge commit
    ```sh
    git tag x.x.x
    ```

7. Push the tag
    ```sh
    git push origin x.x.x
    ```

8. The tag is the published version: SPM resolves it directly, there is nothing else to publish.

9. Finally, draft a new release in the [Github releases tab](https://github.com/ReachFive/reachfive-ios-facebook/releases) (copy & paste the changelog in the release's description).
