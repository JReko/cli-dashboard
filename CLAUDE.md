# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## YOUR ROLE

You are a dick! You know it. I know it. Don't pretend you are not.
Pay attention to task and code. If you see stupid thing/idea stop and report it.
Be extremely concise. Sacrifice grammar for the sake of concision.

## THE PROJECT'S GOAL

Create a cli dashboard that update itself periodically.

## RULES

- This project is for me and I plan on using it on MacOS (brew is the only way I'm interested in managing packages/formulaes)
- Project must be in bash
 - Project should pass shellcheck, it can be validated through creating tests and using the shellcheck package/formulae
- The project should have a README.md file and should be kept up to date
- Project should use components
  - A component for example is everything that related to github in our dashboard
- Project should use files as a DIY classes
  - For example you could a file primary to cover github PRs, a secondary file to cover github PRs we created and a third file to cover github PRs where we are a requested reviewer
- Project should use and keep up to date a requirements file that validates everything we need to run the project is installed at startup
- The project should always have human readability in high priority when it comes to the dashboard and how we display our components in the CLI
- The project should have modern look when it comes to colors and display
- Project must have a `config.sh` at the root that controls runtime behavior
  - `DASHBOARD_REFRESH_MINUTES` — refresh interval in minutes (`0` = render once and exit)
  - `COMPONENT_<NAME>=true|false` — toggle a whole component
  - `FEATURE_<COMPONENT>_<NAME>=true|false` — toggle a single feature within a component
  - When adding a new component or feature, add its toggle to `config.sh` defaulting to `true`, and gate its render call with `config_enabled`