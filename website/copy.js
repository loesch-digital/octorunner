const command = document.querySelector('#brew-command');
const copyButton = document.querySelector('#copy-command');
const copyStatus = document.querySelector('.copy-status');

copyButton.hidden = false;
copyButton.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(command.textContent);
    copyStatus.textContent = 'Copied to clipboard.';
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(command);
    selection.removeAllRanges();
    selection.addRange(range);
    copyStatus.textContent = 'Command selected. Copy it with your keyboard.';
  }
});
