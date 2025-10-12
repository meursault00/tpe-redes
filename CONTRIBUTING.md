# Contributing Guidelines

## Team Members

- Bengolea, Iñaki (63515) - ibengolea@itba.edu.ar
- Braun, Santos (62090) - sbraun@itba.edu.ar
- López Menardi, Félix (62707) - flopezmenardi@itba.edu.ar

## Development Workflow

### Branch Strategy

- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/*` - Individual features

### Commit Messages

Use conventional commit format:

```
type(scope): subject

body (optional)
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

Examples:
```
feat(playbooks): add scale.yml for cluster scaling
fix(inventory): correct worker node IP addresses
docs(readme): update installation instructions
```

## Testing

Before committing:

1. Test playbook syntax:
   ```bash
   ansible-playbook --syntax-check playbooks/<playbook>.yml
   ```

2. Run in check mode:
   ```bash
   ansible-playbook --check playbooks/<playbook>.yml
   ```

3. Test on local VMs before pushing

## Code Style

- Use YAML lint for playbook formatting
- Follow Ansible best practices
- Keep playbooks idempotent
- Document complex tasks with comments

## Pull Request Process

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit PR with description of changes
5. Wait for team review

## Questions?

Contact any team member via email or discuss in lab sessions.
