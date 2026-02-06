# delta.lua

# Requirements
### Core functionality
Given a diff, output a readonly neovim buffer with diff two tier highlighting, while maintaining the original highlighting from treesitter and lsp
the two tier highlighting and the formatting of hunk headers and such should equal the original delta pager

### diffing algorithm stuff
if using for git, use git diff; else, use vim.text.diff. Use myers algorthm for vim.text.diff, and linematch must be off. consider explicitly setting those for git as well
if we want consistency, we could use vim.text.diff for git as well, and just use git to get the files and the indexes and stuff. Seems like git diff is able to diff directories, while vim.text.diff cannot. But this can easily be spun up if we can get what files we need to diff.

### syntax highlighting
currently the approach is to disable treesitter on the scratch buffer and apply the exact highlighting via extmarks that is on the source buffer onto the new buffer. This avoids the tradeoff of having bad highlighting on context that is incomplete (for example, the start of a function without the end) that is noted in another plugin diffs.nvim that tries to do a similar thing of treesitter highlighting in a unified diff file. However, this may come with the tradeoff of lsp may not work without treesitter active and parsing; if I am hard coding the rerouting by column and row indexes though, this may not be an issue.

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

