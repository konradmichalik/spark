document.querySelectorAll('.copy').forEach((button) => {
  button.addEventListener('click', async () => {
    const status = document.querySelector('.status');
    try {
      await navigator.clipboard.writeText(button.dataset.cmd);
      button.classList.add('copied');
      status.textContent = 'Copied to the clipboard';
    } catch {
      status.textContent = 'Copy failed, select the command instead';
    }
    setTimeout(() => {
      button.classList.remove('copied');
      status.textContent = '';
    }, 2000);
  });
});
