For a public uploader, simply build using `dub`

For a private uploader, uncomment `version = Public;` in app.d and fill in a hash in the secret enum. You will probably want to change the `hash` function to anything else to prevent ID lookup.