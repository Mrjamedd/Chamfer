# Mixed-format test note

This note deliberately combines structures that should survive cleanup. The prose has a few mistake but the addresses and payloads below must stay exact.

## References

- Project page: [Chamfer notes](https://example.com/projects/chamfer?q=keep%20exact)
- Related note: [[Pipeline Safety]]
- Asset: ![[diagram-v3.png]]
- Tag: #integration/testing

## Checklist

- [x] discover the note
- [ ] mask protected regions
- [ ] produce a real diff
- [ ] approve then undo it

Priority:: high

```python
def preserve_spacing(value: str) -> str:
    # The code block should never be rewritten.
    return value.replace("  ", " ")
```

Outside the code, this sentance can be corrected. The final paragraph is mostly clean so a spelling-only pass should make one small change rather than rewriting the whole note.
