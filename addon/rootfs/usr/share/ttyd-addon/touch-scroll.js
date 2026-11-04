/*
 * Claude Code add-on: swipe to scroll on touch screens (option mobile_scroll).
 *
 * The ttyd service adds this script to ttyd's page when mobile_scroll is on.
 * Claude Code turns on mouse tracking, and xterm.js 5 (ttyd 1.7.7) ignores
 * touch gestures while an application tracks the mouse, so a swipe scrolls
 * nothing on a phone. This script takes over vertical swipes on the terminal
 * and turns them into mouse wheel events, one per row of finger travel.
 * xterm.js then does exactly what it does for a mouse wheel: it sends wheel
 * reports to the application (Claude Code, or tmux with mobile_tabs), sends
 * arrow keys in the alternate screen, or scrolls its own history.
 *
 * Taps and two-finger gestures are left alone, so tapping to open the
 * keyboard, the mobile_tabs bar and pinch zoom keep working. Devices without
 * a touch screen are not affected.
 *
 * Uses only the public xterm.js API (window.term is the terminal of ttyd).
 * Remove this file once the Alpine ttyd package ships xterm.js 7, which sends
 * touch scrolls as wheel reports itself (xterm.js main branch, not released).
 */
(function () {
  'use strict';

  var coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
  if (!coarse && !('ontouchstart' in window)) {
    return;
  }

  // Finger travel in pixels before a touch counts as a swipe and not a tap
  var SWIPE_THRESHOLD = 10;

  function rowHeight(term) {
    var screen = term.element.querySelector('.xterm-screen');
    if (screen && term.rows > 0 && screen.clientHeight > 0) {
      return screen.clientHeight / term.rows;
    }
    return 16;
  }

  function attach(term) {
    if (!term || !term.element || !term.element.parentElement || term.claudeCodeTouchScroll) {
      return;
    }
    term.claudeCodeTouchScroll = true;

    var element = term.element;
    var screen = element.querySelector('.xterm-screen') || element;
    var startX = 0;
    var startY = 0;
    var lastY = 0;
    var pending = 0;
    var tracking = false;
    var swiping = false;

    function wheel(touch, deltaY) {
      screen.dispatchEvent(new WheelEvent('wheel', {
        deltaY: deltaY,
        deltaMode: 0, // pixels
        clientX: touch.clientX,
        clientY: touch.clientY,
        bubbles: true,
        cancelable: true
      }));
    }

    function inside(event) {
      return element.contains(event.target);
    }

    // Capture phase on the parent, so the touch handlers of xterm.js on the
    // terminal element never see a swipe (no double scrolling)
    var parent = element.parentElement;

    parent.addEventListener('touchstart', function (event) {
      tracking = inside(event) && event.touches.length === 1;
      swiping = false;
      if (tracking) {
        startX = event.touches[0].clientX;
        startY = lastY = event.touches[0].clientY;
        pending = 0;
      }
    }, { capture: true, passive: true });

    parent.addEventListener('touchmove', function (event) {
      if (!tracking || event.touches.length !== 1) {
        tracking = false;
        return;
      }
      var touch = event.touches[0];
      event.stopPropagation();
      if (!swiping) {
        var dy = Math.abs(touch.clientY - startY);
        var dx = Math.abs(touch.clientX - startX);
        if (dy < SWIPE_THRESHOLD || dy < dx) {
          return;
        }
        swiping = true;
        lastY = startY;
      }
      event.preventDefault();
      var height = rowHeight(term);
      // Finger up = content up = wheel down (positive deltaY)
      pending += lastY - touch.clientY;
      lastY = touch.clientY;
      while (Math.abs(pending) >= height) {
        var step = pending > 0 ? height : -height;
        wheel(touch, step);
        pending -= step;
      }
    }, { capture: true, passive: false });

    function end(event) {
      if (swiping) {
        event.stopPropagation();
      }
      tracking = false;
      swiping = false;
    }
    parent.addEventListener('touchend', end, { capture: true, passive: true });
    parent.addEventListener('touchcancel', end, { capture: true, passive: true });
  }

  // ttyd creates its terminal after the page has loaded
  setInterval(function () {
    attach(window.term);
  }, 1000);
})();
