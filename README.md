# delta.lua

# Requirements
### Core functionality
Given a diff, output a readonly neovim buffer with diff two tier highlighting, using treesitter and (if possible) lsp highlighting. formatting of hunk headers and such should equal the original delta pager, or at least be close; wiggle room is available for technical constraints

### diffing algorithm stuff
if using for git, use git diff; else, use vim.text.diff. Use myers algorthm for vim.text.diff, and linematch must be off. consider explicitly setting those for git as well
if we want consistency, we could use vim.text.diff for git as well, and just use git to get the files and the indexes and stuff. Seems like git diff is able to diff directories, while vim.text.diff cannot. But this can easily be spun up if we can get what files we need to diff.

### syntax highlighting
the approach:
1. Create a buffer, with formatted diff. create a mapping for where each row and column in the diff corresponds to, in terms of the source
example: table<{filename, 'new' | 'old', col_delta}, row> 
2. for each filename + 'new' | 'old' combination, get the treesitter hl_groups WITHOUT creating a new buffer
3. sit those hl_groups in this sort of mapping
example: table<(filename, 'new' | 'old'), table<row, {start_col, end_col, hl_group}>>
4. after each file is parsed, immediately apply those hl_groups to the formatted buffer using the mapping. 
example: tokens[{filename, 'new'}][row]


### integrations
currently Deltaview.nvim uses the delta binary; this should be a drop in substitute, with slight differences in cursor tracking (due to line number and not having to parse them anymore, and instead we can use the buffer itself)
this should function similarly to mini.diff, such that it can be used for codecompanion ai diffs. Other plugins who wants diffs should be able to use this with one or a couple functions. ai can input a diff language string, and get a buffer back, and choose how to display it. git differs can input their diff language string, get a buffer back, and choose how to display it. 

delegation of responsibility; this will handle the creation of the buffer, and the routing of lsp requests. clients will have to specify whether the before or after of their code corresponds to the "real" code in their project, then the lsp intermediary will take requests sent to it and find the lsp provided by the client, then route that request to it. I only need to know the before or after to know if hover is used on text in my buffer, whether i need to route that request or not.

a client like deltaview is now primarily responsible for the user experience (it always was lowk); cursor tracking, buffer popovers, file menus, etc.
note that with git diffs (or i guess diffs in general) can be with multiple files. need to route that properly aswell

### line numbers
the original delta pager has after lines, before lines, and both on context lines
I will be controlling the neovim gutter to have both as well (maybe iwth statuscolumn)

### buffer management
creates scratch buffers; it is up to the client how they want to display the buffer. 

### LSP integration
If the diff is a git diff, the "after" corresponds to real code", an intermediary lsp will be able to route requests from the custom buffer to to the real corresponding code. The LSP functionality I would like to support are
textDocument/hover 	hover
textDocument/signatureHelp 	signature_help
textDocument/definition 	definition
textDocument/implementation 	implementation
textDocument/declaration 	declaration
textDocument/documentSymbol 	document_symbol
textDocument/typeDefinition 	type_definition
textDocument/references 	references

no write functionality; aka, no completion, no rename

if the diff is not a git diff, and the "before" corresponds to real code (eg. ai diffs that are trying to apply a patch), the intermediary lsp will be able to route requests on the "before" code to the real corresponding code

