# Flag attributes

Feature-flag evaluation attributes on spans.
Values are the boolean evaluation result; the `<key>` suffix is the flag name.
Product/SDK evaluation tracking is documented under concepts and
`sdks/*/feature-flags.md` — do not confuse these attributes with generic tags.

| Key | Type | Brief |
| --- | --- | --- |
| `flag.evaluation.<key>` | `boolean` | An instance of a feature flag evaluation. The value of this attribute is the boolean representing the evaluation result. The <key> suffix is the name of the feature flag. |
