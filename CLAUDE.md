# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

Build and run the application:
```bash
xcodebuild -project mercury-macos.xcodeproj -scheme mercury-macos -configuration Debug build
```

Open in Xcode:
```bash
open mercury-macos.xcodeproj
```

Run from Xcode using Cmd+R or from the Product menu.

## Project Architecture

Mercury is a macOS application built with SwiftUI targeting macOS 15.2+. The app appears to be designed as a journaling or text editing application with the following architecture:

### Core Structure
- **mercuryApp.swift**: Main app entry point with custom window configuration (hidden titlebar, center positioning, 1100x600 default size)
- **AppDelegate.swift**: Handles macOS-specific window management, particularly fullscreen state handling and window centering
- **ContentView.swift**: Root view component (currently displays placeholder content)

### Data Models
- **HumanEntry**: Core data structure representing journal entries with UUID, date, filename, and preview text. Includes factory method `createNew()` for generating new entries with timestamped filenames
- **AppState.swift**: Contains global app state variables including entries array, text content, and fullscreen state

### Architecture Patterns
- Uses SwiftUI's state management with `@State` for simple values
- Follows MVVM pattern typical for SwiftUI apps
- Structured with separate folders for Models, Services, Views, and Utils
- Uses AppKit integration for macOS-specific functionality

### Key Technical Details
- Bundle identifier: `hussamfyi.Mercury`
- Sandboxed application with read-only file access permissions
- SwiftUI previews enabled for development
- Uses modern SwiftUI features like `.windowStyle(.hiddenTitleBar)` and `.windowToolbarStyle(.unifiedCompact)`

### Development Notes
- Many service and view files are currently empty (placeholder files)
- The app currently shows "Hello, bitches!" placeholder text
- Filename generation uses UUID and timestamp format: `[UUID]-[YYYY-MM-DD-HH-MM-SS].md`
- Date display uses "MMM d" format (e.g., "Apr 15")

## Linear Project Management Guidelines

When working with Linear for project management and task tracking, follow these specific guidelines:

### Project Structure
- **Projects**: Use for major features or components (e.g., "Mercury X API Authentication Component")
- **Issues**: Break projects into logical phases or major workstreams
- **Sub-issues**: Break issues into specific, actionable tasks that can be completed in 1-3 days

### Issue Hierarchy Rules
1. **Parent Issues** should represent major phases or feature areas
2. **Sub-issues** should be:
   - Specific, actionable tasks
   - Completable within 1-3 days
   - Have clear acceptance criteria
   - Include relevant file paths and technical details

### Naming Conventions
- **Projects**: Use descriptive names with component/feature focus
- **Issues**: Include phase information and time estimates where relevant
- **Sub-issues**: Start with action verbs (Implement, Create, Build, Test, etc.)

### Labels and Priority
- Use "Feature" label for new functionality
- Use "Bug" label for fixes
- Use "Improvement" label for enhancements
- Set priority based on project phase: High (Phases 1-3), Medium (Phases 4-6)

### Documentation Standards
- Include technical implementation details in issue descriptions
- Reference specific files and classes that will be modified
- Add acceptance criteria and success metrics
- Link related PRs and branches when available

### Git Integration
- Use Linear's auto-generated branch names for consistency
- Reference Linear issue IDs in commit messages
- Connect PRs to Linear issues for tracking

## Context Files Reference

When working on specific features or tasks, always read these key files first to understand current state and requirements:

### Project Planning & Requirements
- `@documentation/x-api-authentication/prd-x-api-authentication.md` - Complete PRD for X API Authentication Component
- `@documentation/x-api-authentication/tasks-prd-x-api-authentication.md` - Detailed task breakdown with file references and completion status
- `@documentation/mercury-core-app/prd-mercury-core-app.md` - Complete PRD for the Mercury Core App (if exists)

### Critical Cursor Rules (Read These First)
- `.cursor/rules/create-prd.mdc` - Process for generating PRDs from user prompts with clarifying questions
- `.cursor/rules/generate-tasks.mdc` - Process for breaking down PRDs into actionable task lists
- `.cursor/rules/generate-linear-issues.mdc` - Process for creating Linear projects, issues, and sub-issues from documentation
- `.cursor/rules/process-task-list.mdc` - Guidelines for working through tasks one at a time with user approval

**Key Workflow Rules from Cursor:**
1. **PRD Creation**: Always review `.cursor/rules/create-prd.mdc` before writing PRDs and ask clarifying questions. Create project folder `/documentation/[feature-name]/`
2. **Task Generation**: Always review `.cursor/rules/generate-tasks.mdc` to generate tasks. Create parent tasks first, wait for "Go" confirmation, then generate sub-tasks according to the rules.
3. **Linear Integration**: Always review `.cursor/rules/generate-linear-issues.mdc` when user requests Linear project creation. Copy complete PRD content, create numbered parent issues, and sub-issues using parentId.
4. **Task Execution**: Always review `.cursor/rules/process-task-list.mdc` to execute the tasks. Complete ONE sub-task at a time, mark completed with `[x]` in the task list and ask for permission before proceeding with the next task.
5. **File Maintenance**: Update relevant files section and task completion status after each task

## Linear Integration Workflow

### When to Use Linear Integration
- After PRD and tasks files are created in `/documentation/[feature-name]/`
- When user explicitly requests "create Linear project/issues" 
- Before beginning task execution to enable proper issue tracking

### Process Overview
1. **Read Documentation**: Review complete PRD and tasks files
2. **Create Project**: Use complete PRD content as Linear project description
3. **Create Parent Issues**: Map numbered tasks (1.0, 2.0, etc.) to Linear issues
4. **Create Sub-issues**: Map sub-tasks (1.1, 1.2, etc.) using parentId parameter
5. **Dual Maintenance**: Keep markdown and Linear status synchronized

### Critical Requirements ⚠️
- **Complete PRD Copy**: Linear project description MUST contain entire PRD content (never truncate)
- **Exact Title Mapping**: Use exact task titles from markdown files
- **Parent-Child Hierarchy**: Use `parentId` parameter for sub-issues
- **Junior Developer Focus**: All descriptions must be actionable for junior developers
- **File References**: Include specific file paths and technical details

### Documentation Structure
- **Project Folders**: Each feature gets its own folder: `/documentation/[feature-name]/`
- **PRD Storage**: `prd-[feature-name].md` stored in project folder
- **Tasks Storage**: `tasks-[prd-file-name].md` stored in same project folder

### Task to Linear Issue Mapping
1. **Linear Projects**: Create one project per feature with complete PRD as description
2. **Parent Issues**: Each numbered task (e.g., "1.0 Set up X Developer Portal") becomes a Linear issue
3. **Sub-issues**: Each sub-task (e.g., "1.1", "1.2") becomes a sub-issue using parentId
4. **Descriptions**: Add actionable, junior-developer-friendly descriptions with file paths and acceptance criteria

### Status Synchronization Rules
1. **Dual Updates**: When marking tasks complete in markdown, also update Linear issue status to "Done"
2. **Single Source of Truth**: Maintain consistency between markdown files and Linear
3. **Real-time Updates**: Update Linear status immediately after completing tasks
4. **Recovery**: If status gets out of sync, markdown files are the authoritative source

### Common Pitfalls to Avoid
- ❌ Truncating PRD content in Linear project description
- ❌ Creating parent issues without corresponding sub-issues
- ❌ Missing parentId parameter for sub-issues
- ❌ Vague descriptions without file references or acceptance criteria
- ❌ Inconsistent status between markdown and Linear

### Current Codebase Structure
- `mercury-macos/MercuryApp.swift` - Main app entry point and configuration
- `mercury-macos/AppDelegate.swift` - macOS window management
- `mercury-macos/Models/AppState.swift` - Global app state management
- `mercury-macos/Views/ContentView.swift` - Root view component
- `mercury-macos/Models/AuthenticationModels.swift` - Authentication data models (if exists)

### Authentication Implementation Files (Read Before Working on Auth Features)
- `mercury-cli-auth/` - CLI authentication testing tool directory
- `mercury-macos/Authentication/` - Main app authentication components
- `mercury-macos/Services/NetworkMonitor.swift` - Network connectivity monitoring
- `mercury-macos/Extensions/` - OAuth integration extensions

### Instructions for Claude Code
**Before starting any authentication-related task:**
1. Read the PRD and task files to understand requirements and current progress
2. Check the specific files mentioned in the task breakdown
3. Review existing authentication components to understand current architecture
4. Always check git status to see what's been modified recently

**Use these patterns to reference files:**
- `@filename` for files in project root or commonly referenced files
- Full relative paths for specific implementation files
- Directory references with `/` for exploring entire modules