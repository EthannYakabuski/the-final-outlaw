# The Final Outlaw: GitHub Pages and iframe use

Stable project URL: **https://ethannyakabuski.github.io/the-final-outlaw/**

## Build and deployment

The user authorized this repository's public Web deployment on 2026-11-05.
`.github/workflows/build-and-deploy.yml` keeps the existing import, service/game
tests, strict diagnostics, Android debug AAB validation and Web export gates.
Only a successful main-branch build can deploy its `build/web` artifact to the
`github-pages` environment. Source, raw logs, real saves, signing material and
private local evidence are not uploaded as the Pages artifact. `LICENSE`, `NOTICE`
and `LICENSES/` accompany the exported game.

`build-info.json` at the project URL records only `source_commit` and `repository`.
Compare its SHA to the successful Actions deployment; a workflow file or an HTTP
200 response alone is not evidence that the expected game revision is live.
Repository Settings / Pages must use **GitHub Actions** as its publishing source.
Keep environment protection rules intact; a required approval must be handled
normally. No custom domain, website edit or app-store publication is part of this setup.

## Embedding later

The website remains unchanged. A later owner website update can use an iframe such as:

```html
<iframe src="https://ethannyakabuski.github.io/the-final-outlaw/" title="The Final Outlaw"
        width="540" height="960" allow="autoplay; fullscreen" allowfullscreen>
</iframe>
```

Keep a portrait aspect ratio and responsive dimensions; click/tap inside the game
to give it focus and unlock browser audio. Browser autoplay and fullscreen still
follow browser policy. If the parent website adds sandbox/CSP restrictions, review
those restrictions deliberately rather than disabling browser security. Storage
may be blocked or partitioned in cross-site/private iframe contexts, so local save
retention must be checked in the actual destination website/browser. There is no
claim of cloud synchronization or cross-device saves.

The current Web preset is single-threaded (`variant/thread_support=false`) with
native extensions disabled. It does not need SharedArrayBuffer/cross-origin
isolation headers. Actual response headers and cross-origin iframe behavior need
their own deployment/browser checks; static build success does not establish them.

## Controls and native services

Keyboard: WASD/arrows move, J fires, R reloads, Space dashes, Escape pauses. Moving while shooting uses simultaneous keyboard input or separate touch controls; the current game is not one-pointer-only.

AdMob and Google Play Games remain Android-only. Web does not request those native
ads, sign in to Play Games or fabricate rewarded benefits; local play and browser
storage remain the fallback. This deployment changes no gameplay, production IDs,
debug test-ad routing, genuine profile or Android signing setting.

Load-only, actual interaction, audio, iframe save retention and human/device
acceptance are separate results. Verify the live deployed revision and document
the actual scope of every check; older native screenshots/QA are not current Web evidence.
