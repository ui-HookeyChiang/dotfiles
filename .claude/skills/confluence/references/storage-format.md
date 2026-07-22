# Confluence Storage Format

Confluence uses **Storage Format** (XHTML-based) for page bodies, NOT Jira's ADF
(Atlassian Document Format). For user-provided plain text, wrap each paragraph in
`<p>` tags. For richer content, use the XHTML elements and macros below.

## Examples

```xml
<p>Paragraph text</p>
<h2>Heading</h2>
<ul><li>List item 1</li><li>List item 2</li></ul>
<table><tbody><tr><th>Header</th></tr><tr><td>Cell</td></tr></tbody></table>
<ac:structured-macro ac:name="code"><ac:plain-text-body><![CDATA[code here]]></ac:plain-text-body></ac:structured-macro>
```

## mentions

To mention a user inside a comment or page body:

```xml
<ac:link><ri:user ri:userkey="USER_KEY"/></ac:link>
```

## strip-html

To convert a storage-format body to readable plain text (strip HTML tags):

```bash
# Extract and display readable body content
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content/$PAGE_ID?expand=body.storage,version,ancestors,space" \
  | jq -r '.body.storage.value' \
  | sed -e 's/<br[^>]*>/\n/g' -e 's/<\/p>/\n/g' -e 's/<\/h[1-6]>/\n/g' -e 's/<\/li>/\n/g' -e 's/<\/tr>/\n/g' -e 's/<[^>]*>//g' -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e '/^$/d'
```
