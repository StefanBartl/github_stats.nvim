# Quickstart

First, the token — an environment variable is the recommended shape:

```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

No token yet, or unsure it has the right scope? [Preparation](configurations/PREPARATION.md)
walks through creating one and verifying it reaches the traffic API.

Then, in Neovim, fetch once by hand and look at the result:

```vim
:GithubStats fetch force
:GithubStats dashboard
```

Verify your setup any time with:

```vim
:checkhealth github_stats
```

From here: [What you get with the defaults](what-you-get.md) for the commands
worth knowing on day one, or the [command reference](commands.md) for the full
`:GithubStats <subcommand>` tree.
