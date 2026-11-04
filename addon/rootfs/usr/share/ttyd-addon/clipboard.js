/*
 * Claude Code add-on: copy into the browser clipboard (OSC 52).
 *
 * The ttyd service adds this script to ttyd's page (see ttyd/run). When
 * Claude Code copies text inside tmux, it runs `tmux load-buffer -w`, and
 * tmux sends the text to the terminal as an OSC 52 sequence; tmux copy mode
 * does the same. ttyd 1.7.7 bundles xterm.js 5 without the clipboard addon,
 * so xterm.js drops these sequences and nothing reaches the clipboard. This
 * handler writes them into the browser clipboard instead.
 *
 * tmux forwards only its own copies (set-clipboard "external", the default),
 * so text that a program merely prints cannot change the clipboard. Requests
 * to read the clipboard are never answered.
 *
 * Uses only the public xterm.js API (window.term is the terminal of ttyd).
 * Remove this file once the Alpine ttyd package ships @xterm/addon-clipboard
 * (ttyd's main branch has it, no release yet).
 */
(function () {
  'use strict';

  // Longest base64 payload accepted, about 768 KB of text
  var MAX_LENGTH = 1048576;

  function decode(base64) {
    var binary = atob(base64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return new TextDecoder().decode(bytes);
  }

  // For pages without the Clipboard API (plain HTTP is not a secure context)
  function copyWithTextarea(text, term) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.top = '0';
    area.style.left = '0';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try {
      // false: the browser refused the copy, for example without a recent
      // keypress or tap
      if (!document.execCommand('copy')) {
        console.warn('[claude-code] copy failed: the browser refused it');
      }
    } catch (e) {
      console.warn('[claude-code] copy failed:', e);
    }
    document.body.removeChild(area);
    term.focus();
  }

  function copy(text, term) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () {
        copyWithTextarea(text, term);
      });
    } else {
      copyWithTextarea(text, term);
    }
  }

  function attach(term) {
    if (!term || !term.parser || term.claudeCodeClipboard) {
      return;
    }
    term.claudeCodeClipboard = true;
    // data is "<selection>;<base64>", for example "c;aGVsbG8=" or ";aGVsbG8="
    term.parser.registerOscHandler(52, function (data) {
      var separator = data.indexOf(';');
      var base64 = separator < 0 ? '' : data.slice(separator + 1);
      if (base64 && base64 !== '?' && base64.length <= MAX_LENGTH) {
        try {
          copy(decode(base64), term);
        } catch (e) {
          console.warn('[claude-code] copy failed:', e);
        }
      }
      return true;
    });
  }

  // ttyd creates its terminal after the page has loaded
  setInterval(function () {
    attach(window.term);
  }, 1000);
})();
