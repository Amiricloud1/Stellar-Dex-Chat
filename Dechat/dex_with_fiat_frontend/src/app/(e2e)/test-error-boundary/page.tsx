'use client';

import { useEffect, useRef, useState } from 'react';
import ErrorBoundary from '@/components/ErrorBoundary';

/** Child that crashes on demand */
function BombChild({ shouldThrow }: { shouldThrow: boolean }) {
  if (shouldThrow) {
    throw new Error('Deliberate test crash');
  }
  return (
    <p data-testid="child-content" className="text-sm text-green-700">
      Child rendered successfully.
    </p>
  );
}

/**
 * Test harness page for ErrorBoundary E2E tests.
 *
 * A "Throw Error" button triggers a crash inside ErrorBoundary so tests can
 * verify the fallback UI, retry/reload behaviour, and keyboard shortcuts.
 *
 * A "Reset" button resets the local `shouldThrow` flag so tests can check the
 * `onRetry` path without reloading the page.
 *
 * Keyboard-operable recovery flow:
 * - On failure, focus moves to the recovery (retry) action inside the fallback.
 * - On retry/dismiss, focus is restored to the trigger button that caused the
 *   failure so keyboard users can continue without a pointer.
 * - Status updates are announced through a single live region to avoid
 *   duplicated announcements.
 */
export default function TestErrorBoundaryPage() {
  const [shouldThrow, setShouldThrow] = useState(false);
  const [retryCount, setRetryCount] = useState(0);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const fallbackRef = useRef<HTMLDivElement>(null);

  const handleRetry = () => {
    setShouldThrow(false);
    setRetryCount((c) => c + 1);
  };

  // Move focus predictably: into the fallback recovery action on failure,
  // and back to the trigger on recovery.
  useEffect(() => {
    if (shouldThrow) {
      const retryButton = fallbackRef.current?.querySelector<HTMLElement>(
        '[data-testid="error-retry"], button',
      );
      retryButton?.focus();
    } else if (retryCount > 0) {
      triggerRef.current?.focus();
    }
  }, [shouldThrow, retryCount]);

  return (
    <main className="min-h-screen p-6 flex flex-col gap-4">
      <h1 className="text-lg font-semibold">ErrorBoundary Test Harness</h1>

      <div className="flex gap-3">
        <button
          ref={triggerRef}
          type="button"
          data-testid="trigger-error"
          onClick={() => setShouldThrow(true)}
          className="px-3 py-1 text-sm rounded border bg-red-50 border-red-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
        >
          Throw Error
        </button>
        <button
          type="button"
          data-testid="reset-error"
          onClick={() => setShouldThrow(false)}
          className="px-3 py-1 text-sm rounded border focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
        >
          Reset
        </button>
      </div>

      {/* Single live region for status updates to avoid duplicate announcements. */}
      <p
        role="status"
        aria-live="polite"
        data-testid="status-live-region"
        className="text-sm text-blue-700"
      >
        {shouldThrow
          ? 'Transaction failed. Recovery action available.'
          : retryCount > 0
            ? `Retry triggered ${retryCount} time${retryCount === 1 ? '' : 's'}.`
            : ''}
      </p>

      <div ref={fallbackRef}>
        <ErrorBoundary
          onRetry={handleRetry}
          retryLabel="Try Again"
          title="Something went wrong."
          message="Please refresh the page."
        >
          <BombChild shouldThrow={shouldThrow} />
        </ErrorBoundary>
      </div>
    </main>
  );
}
