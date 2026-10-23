# Product

## Facts

| Fact            | Value                    | Asked by |
| --------------- | ------------------------ | -------- |
| product.kind    | mac-app                  | router   |
| accounts        | no                       | router   |
| billing         | polar                    | router   |
| analytics       | openpanel                | router   |
| audience.locale | en                       | router   |
| product.name    | Agent Caffeine           | router   |
| site.url        | https://caffeinagent.com | router   |

`product.kind` is `mac-app`: a 7-day free trial, then a license key paid once (Polar checkout, `apps/web/src/lib/pricing.ts`). `analytics` is OpenPanel on the live host only, through the site's `/api/op` proxy.

## Blocks

None applied yet.
