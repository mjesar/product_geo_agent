# Shopify Storefront API — Auth Setup

How we got a working Storefront API access token for the sandbox store, using the
current (2026) Dev Dashboard custom-app flow. This changed significantly from the old
"legacy custom apps" flow — there is no longer a UI button that directly generates a
Storefront token. Keep this doc for reference if setting this up again on a new store,
or if the token ever needs to be regenerated.

## Why this was harder than expected

As of January 1, 2026, merchants can no longer create *new* legacy custom apps (the old
flow with a simple "Storefront API integration → Configure → reveal token" UI). New
custom apps go through **Dev Dashboard** instead, which:
- Doesn't show a Storefront API token anywhere in its UI for direct generation
- Only shows Client ID + Client Secret (OAuth credentials), not an Admin API access token
- Has a "Storefront API" section that just links to a scope-request form for
  *restricted* scopes (subscriptions, payment mandates) — a dead end for what we needed

The actual Admin API access token (needed as a stepping stone to create a Storefront
token) is normally shown **once**, at install time — and if that install redirects
somewhere with no visible page (e.g., a placeholder `redirect_uri`), it's easy to lose.

## The working flow

### 1. Create the custom app
- Store admin → Settings → Apps and sales channels → Develop apps → this now redirects
  to Dev Dashboard
- Create app → select "Custom" → select the store → this generates an install URL like:
  ```
  https://admin.shopify.com/oauth/install_custom_app?client_id=...&signature=...
  ```

### 2. Grant the right scopes
In Dev Dashboard → the app → Versions → create/edit a version, add scopes:
```
unauthenticated_read_product_listings,unauthenticated_read_product_tags,unauthenticated_read_content
```
These are the *unauthenticated* scopes — what the Storefront API actually uses. Create
the version, then **Release** it. Scope changes require a new version + release, and
the merchant needs to re-approve the app with the new scopes.

### 3. Set an allowed redirect URL
In the same version config, under "Allowed redirection URL(s)", add:
```
https://example.com
```
This is just a landing page we control the meaning of — we're going to read the
authorization `code` out of the URL bar after redirect, not actually use example.com
for anything.

### 4. Manually trigger the OAuth authorize flow
Build this URL (fill in your actual client_id, scopes, and store domain):
```
https://{store}.myshopify.com/admin/oauth/authorize?client_id={CLIENT_ID}&scope=unauthenticated_read_product_listings,unauthenticated_read_product_tags,unauthenticated_read_content&redirect_uri=https://example.com&state=setup123
```
Paste it into the browser while logged into the store admin. It redirects to
`https://example.com/?code=...&shop=...&state=...` — **copy the `code` value from the
URL bar**. It's short-lived (expires within a couple minutes), so move to the next step
quickly.

### 5. Exchange the code for an Admin API access token
```bash
curl -X POST https://{store}.myshopify.com/admin/oauth/access_token \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "YOUR_CLIENT_ID",
    "client_secret": "YOUR_CLIENT_SECRET",
    "code": "THE_CODE_FROM_STEP_4"
  }'
```
Response:
```json
{
  "access_token": "shpca_...",
  "scope": "unauthenticated_read_product_listings,unauthenticated_read_product_tags,unauthenticated_read_content"
}
```
Confirm the `scope` matches what you granted. This `shpca_...` token is the Admin API
access token — but note it's scoped to *unauthenticated* access only, since that's all
we requested. It's not a general-purpose Admin API token for other operations.

### 6. Create the actual Storefront access token
Use the token from step 5 to call the `storefrontAccessTokenCreate` mutation against
the **Admin GraphQL API**:
```bash
curl -X POST https://{store}.myshopify.com/admin/api/2026-07/graphql.json \
  -H "Content-Type: application/json" \
  -H "X-Shopify-Access-Token: shpca_..." \
  -d '{
    "query": "mutation { storefrontAccessTokenCreate(input: { title: \"ProductGeoAgent\" }) { storefrontAccessToken { accessToken } userErrors { field message } } }"
  }'
```
Response contains the real Storefront access token:
```json
{"data":{"storefrontAccessTokenCreate":{"storefrontAccessToken":{"accessToken":"..."},"userErrors":[]}}}
```

### 7. Use it
```
SHOPIFY_STOREFRONT_TOKEN=<the token from step 6>
SHOPIFY_STORE_DOMAIN={store}.myshopify.com
```

Storefront endpoint pattern:
```
https://{store}.myshopify.com/api/{version}/graphql.json
```
(Different from the Admin endpoint used in step 6, which is under `/admin/api/`.)

## Token lifetime
Both the Admin API token (step 5) and the Storefront token (step 6) are long-lived —
no automatic expiration. They stay valid until:
- The app is uninstalled from the store
- The Client Secret is rotated (may invalidate the Admin token's OAuth trust)
- The store is deleted

No need to repeat this flow unless one of the above happens.

## Sanity check
```bash
curl -X POST https://{store}.myshopify.com/api/2026-07/graphql.json \
  -H "Content-Type: application/json" \
  -H "X-Shopify-Storefront-Access-Token: {STOREFRONT_TOKEN}" \
  -d '{"query": "{ products(first: 5) { nodes { title handle description } } }"}'
```
Should return real product data.
