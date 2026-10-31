# GBD Research Hub — Website Publishing Snapshot

This is a **file-only publishing snapshot** of the TOTP-protected research dashboard, prepared for transfer into a **new public repository**.

Website entry: `index.html` redirects to `secure-preview/`.

**Do not copy Git history from this staging branch into the new repository.** This branch was created inside an old repository that has other research code and previously published datasets in its history. Instead, create a brand-new GitHub repository and upload the current files as a new initial commit, or ask the assistant to copy the selected files through GitHub after the new repository exists.

This folder snapshot contains no CSV, private-key material, or research R code. It only includes public HTML/CSS/JavaScript and Supabase's public publishable key. CSV data is read from protected Supabase Storage only after login and TOTP MFA.

License notice for QR encoding is in `secure-preview/vendor/qrcodegen-LICENSE.txt`.

The intended final GitHub Pages URL is:
https://lil48649.github.io/cluster/secure-preview/

Do not change your original `cluster` repository visibility or name until the temporary website has been independently tested.
