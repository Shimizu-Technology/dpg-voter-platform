export function isPlaceholderClerkKey(key: string | undefined) {
  return !key || ['pk_test_xxx', 'pk_test_dummy', 'your_clerk_publishable_key'].includes(key);
}
