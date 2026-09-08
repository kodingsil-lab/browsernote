(() => {
    const appShell = document.getElementById('appShell');
    const collapse = document.getElementById('collapseSidebar');
    const show = document.getElementById('showSidebar');

    collapse?.addEventListener('click', () => {
        appShell.classList.add('sidebar-collapsed');
        localStorage.setItem('browsernote.sidebar', 'collapsed');
    });

    show?.addEventListener('click', () => {
        appShell.classList.remove('sidebar-collapsed');
        localStorage.setItem('browsernote.sidebar', 'open');
    });

    if (localStorage.getItem('browsernote.sidebar') === 'collapsed') {
        appShell.classList.add('sidebar-collapsed');
    }
})();