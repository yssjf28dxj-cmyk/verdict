export function firestoreDatabaseId(projectId: string | undefined): string {
  return projectId === 'verdict-test-1471f' ? 'default' : '(default)';
}
