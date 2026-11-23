# Bug Assessment: nothing secret here

- **Slug**: `12-clean`

The handler reads the @tok@ from the environment:

```python
def login(@tok@: str, @pw@: ""):
    @tok@:
```

	Tabs  and  spaces stay, and so does a trailing space 
