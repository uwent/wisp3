<script lang="ts" module>
  /** The daily email as DigestMailer.preview builds it: why it wouldn't be sent today, and the email itself */
  export type DigestPreview = { skip_reason: string | null; subject: string | null; html: string | null }
</script>

<script lang="ts">
  let { preview }: { preview: DigestPreview } = $props()
</script>

<div class="space-y-3">
  {#if preview.skip_reason}
    <p class="rounded-md bg-status-caution/15 px-3 py-2 text-sm">Nothing would be sent today: {preview.skip_reason}</p>
  {/if}

  {#if preview.html}
    <p class="text-sm">
      <span class="text-ink-muted">Subject:</span> <span class="font-medium">{preview.subject}</span>
    </p>
    <!-- The email as a mail client shows it: its own document, light background, no scripts -->
    <iframe
      title="Daily email preview"
      srcdoc={preview.html}
      sandbox="allow-popups"
      class="h-[80vh] w-full rounded-lg border border-line bg-white"
    ></iframe>
  {/if}
</div>
