(function(){
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---- drag-to-reveal ---- */
  var slider = document.getElementById("rawRefined");
  var range = document.getElementById("rsRange");
  if (slider && range){
    var paint = function(){ slider.style.setProperty("--pos", range.value + "%"); };

    /* The scroll drives the wipe until somebody takes hold of it themselves.
       After that the scroll leaves it alone: pulling the divider out from under
       a hand that is holding it would be rude. */
    var RAW = 84, REFINED = 12;
    var manual = false;
    var queued = false;

    var takeOver = function(){ manual = true; };
    range.addEventListener("pointerdown", takeOver);
    range.addEventListener("touchstart", takeOver, { passive: true });

    var fromScroll = function(){
      queued = false;
      if (manual) return;
      var rect = slider.getBoundingClientRect();
      var travel = rect.height || 1;
      /* the wipe finishes once the hero is 45% gone, so the refined jar is
         still well in view rather than completing off the top of the screen */
      var progress = Math.min(1, Math.max(0, (-rect.top / travel) / 0.45));
      range.value = RAW + (REFINED - RAW) * progress;
      paint();
    };

    if (!reduce){
      window.addEventListener("scroll", function(){
        if (!queued){ queued = true; requestAnimationFrame(fromScroll); }
      }, { passive: true });
      window.addEventListener("resize", fromScroll, { passive: true });
      fromScroll();
    } else {
      range.value = 50;      /* no scroll-linked movement, just a draggable halfway split */
    }

    range.addEventListener("input", paint);
    /* arrow keys move in useful 4% steps, the drag itself stays smooth */
    range.addEventListener("keydown", function(ev){
      var step = 0;
      if (ev.key === "ArrowLeft" || ev.key === "ArrowDown") step = -4;
      if (["ArrowLeft","ArrowRight","ArrowUp","ArrowDown","Home","End"].indexOf(ev.key) > -1) manual = true;
      if (ev.key === "ArrowRight" || ev.key === "ArrowUp") step = 4;
      if (ev.key === "Home") { range.value = 0; paint(); ev.preventDefault(); return; }
      if (ev.key === "End") { range.value = 100; paint(); ev.preventDefault(); return; }
      if (!step) return;
      ev.preventDefault();
      range.value = Math.min(100, Math.max(0, parseFloat(range.value) + step));
      paint();
    });
    paint();
  }

  /* ---- scroll reveals ---- */
  var items = document.querySelectorAll(".r");
  if (reduce || !("IntersectionObserver" in window)){
    items.forEach(function(el){ el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function(entries){
      entries.forEach(function(e){
        if (e.isIntersecting){ e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
    items.forEach(function(el){ io.observe(el); });
  }

  /* ---- supabase ---- */
  var cfg = window.BANINI_CONFIG || {};
  var API = String(cfg.supabaseUrl || "").replace(/\/+$/, "");
  var KEY = String(cfg.supabaseAnonKey || "");
  var connected = Boolean(API && KEY);
  var NOT_CONNECTED = "The book is not open yet. Please try again shortly.";

  if (!connected) {
    console.warn("Banini: supabaseUrl and supabaseAnonKey are empty in config.js, so the waitlist and reservation forms cannot submit. See supabase/README.md.");
  }

  var rpc = function(fn, body){
    if (!connected) return Promise.reject({ hint: NOT_CONNECTED });
    return fetch(API + "/rest/v1/rpc/" + fn, {
      method: "POST",
      headers: {
        "apikey": KEY,
        "Authorization": "Bearer " + KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    }).then(function(res){
      return res.text().then(function(text){
        var data = null;
        try { data = text ? JSON.parse(text) : null; } catch (e) { data = null; }
        if (!res.ok){
          console.error("Banini: " + fn + " returned " + res.status, text);
          throw (data || { hint: "Something went wrong at our end. Please try again in a moment." });
        }
        return data;
      });
    }).catch(function(err){
      /* a failed fetch is a network problem, not something to read out loud */
      if (err && (err.hint || err.message === undefined)) throw err;
      console.error("Banini: " + fn + " could not be reached", err);
      throw { hint: "I could not reach the ordering system. Check your connection and try again." };
    });
  };

  var DEBUG = /[?&]debug=1/.test(location.search);

  var reason = function(err){
    if (!err) return "Something went wrong. Please try again.";
    if (DEBUG) return "[debug] " + JSON.stringify(err);      /* the whole truth, on request */
    if (err.code === "P0001" && err.hint) return err.hint;   /* written for a person */
    if (err.hint && !err.code) return err.hint;              /* our own local errors */
    console.error("Banini: unexpected error from the database", err);
    return "Something went wrong at our end. Please try again in a moment.";
  };

  var EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  var cedi = function(n){
    var whole = Math.round(n * 100) / 100;
    var text = whole % 1 === 0 ? String(whole) : whole.toFixed(2);
    return "\u20B5" + text.replace(/\B(?=(\d{3})+(?!\d))/, ",");
  };

  /* ---- diagnostics, read only ----
     ?debug=1 reports what the browser loaded and whether it can reach the
     database. It writes nothing. */
  if (DEBUG){
    var box = document.createElement("div");
    box.setAttribute("style", "position:fixed;left:12px;right:12px;bottom:12px;z-index:9999;background:#1B3020;color:#FBF7EC;padding:14px 16px;font:12px/1.6 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;border:1px solid #B8923F;max-height:40vh;overflow:auto;pointer-events:none;opacity:.95");
    var say = function(line){ box.textContent += line + "\n"; };
    var mount = function(){ document.body.appendChild(box); };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount); else mount();

    var tag = document.querySelector('script[src*="app.js"]');
    say("page      : " + location.href);
    say("app.js    : " + (tag ? tag.getAttribute("src") : "NOT FOUND"));
    say("config    : " + (window.BANINI_CONFIG ? "loaded" : "MISSING"));
    say("supabase  : " + (API || "EMPTY"));
    say("connected : " + connected);

    if (connected){
      fetch(API + "/rest/v1/sizes?select=slug,price_ghs&order=sort", {
        headers: { "apikey": KEY, "Authorization": "Bearer " + KEY }
      }).then(function(res){
        return res.text().then(function(body){
          say("catalogue : HTTP " + res.status + "  " + body.slice(0, 120));
        });
      }).catch(function(err){ say("catalogue : request failed, " + err.message); });
    }
    say("");
    say("Now fill the form and press the button. The message under it will");
    say("show the exact error rather than the polite version.");
  }

  /* ---- waitlist ---- */
  var form = document.getElementById("signup");
  var note = document.getElementById("formNote");
  if (form && note){
    form.addEventListener("submit", function(ev){
      ev.preventDefault();
      var field = document.getElementById("email");
      var value = field.value.trim();
      var button = form.querySelector("button");
      if (!EMAIL.test(value)){
        note.dataset.state = "error";
        note.textContent = "That email does not look right. Try again.";
        field.focus();
        return;
      }
      button.disabled = true;
      note.dataset.state = "ok";
      note.textContent = "Adding you to the list.";
      rpc("join_waitlist", { p_email: value, p_source: "waitlist" }).then(function(data){
        note.dataset.state = "ok";
        note.textContent = data && data.already_joined
          ? "You are already on the list. I will write when the first run is whipped."
          : "You are on the list. I will write to you when the first run is whipped.";
        form.reset();
      }).catch(function(err){
        note.dataset.state = "error";
        note.textContent = reason(err);
      }).then(function(){
        button.disabled = false;
      });
    });
  }

  /* ---- reservation ---- */
  var rForm = document.getElementById("reserveForm");
  if (rForm){
    var rNote = document.getElementById("reserveNote");
    var linesEl = document.getElementById("lines");
    var emptyEl = document.getElementById("basketEmpty");
    var totalEl = document.getElementById("basketTotal");
    var totalValue = document.getElementById("totalValue");
    var submitBtn = document.getElementById("reserveSubmit");
    var qtyEl = document.getElementById("qty");
    var lines = [];
    var placed = false;

    var checked = function(name){ return rForm.querySelector('input[name="' + name + '"]:checked'); };
    var labelFor = function(input){
      var el = input.closest(".opt").querySelector(".opt-name");
      return el ? el.textContent.trim() : input.value;
    };
    var priceFor = function(size){
      var input = rForm.querySelector('input[name="size"][value="' + size + '"]');
      return input ? parseFloat(input.dataset.price) || 0 : 0;
    };

    var render = function(){
      linesEl.textContent = "";
      var total = 0;
      lines.forEach(function(line, index){
        var cost = priceFor(line.size) * line.quantity;
        total += cost;

        var li = document.createElement("li");
        var name = document.createElement("span");
        name.className = "line-name";
        name.textContent = line.scentName + ", " + line.size;
        var small = document.createElement("small");
        small.textContent = line.quantity + (line.quantity === 1 ? " jar" : " jars");
        name.appendChild(small);

        var cell = document.createElement("span");
        cell.className = "line-cost";
        cell.textContent = cedi(cost);

        li.appendChild(name);
        li.appendChild(cell);

        if (!placed){
          var remove = document.createElement("button");
          remove.type = "button";
          remove.className = "remove";
          remove.textContent = "Remove";
          remove.setAttribute("aria-label", "Remove " + line.quantity + " " + line.scentName + " " + line.size);
          remove.addEventListener("click", function(){
            lines.splice(index, 1);
            render();
          });
          li.appendChild(remove);
        }
        linesEl.appendChild(li);
      });

      emptyEl.hidden = lines.length > 0;
      totalEl.hidden = lines.length === 0;
      totalValue.textContent = cedi(total);
    };

    document.getElementById("addLine").addEventListener("click", function(){
      if (DEBUG) console.log("Banini: add-to-reservation clicked");
      var scent = checked("scent");
      var size = checked("size");
      if (DEBUG) rNote.textContent = "[debug] add clicked. scent=" + (scent && scent.value) +
                                     " size=" + (size && size.value) + " qty=" + qtyEl.value;
      var quantity = Math.min(12, Math.max(1, parseInt(qtyEl.value, 10) || 1));
      qtyEl.value = quantity;
      if (!scent || !size) return;

      var existing = null;
      lines.forEach(function(line){
        if (line.scent === scent.value && line.size === size.value) existing = line;
      });

      if (existing){
        existing.quantity = Math.min(12, existing.quantity + quantity);
      } else if (lines.length >= 10){
        rNote.dataset.state = "error";
        rNote.textContent = "A single reservation holds up to 10 lines. Write to me for anything larger.";
        return;
      } else {
        lines.push({ scent: scent.value, scentName: labelFor(scent), size: size.value, quantity: quantity });
      }

      rNote.dataset.state = "ok";
      rNote.textContent = "Added " + quantity + " " + labelFor(scent) + " " + size.value + ".";
      render();
    });

    rForm.addEventListener("submit", function(ev){
      ev.preventDefault();

      var trap = document.getElementById("company");
      if (trap && trap.value){
        /* Bots fill this hidden field. So, sometimes, does a browser autofill,
           and a human must never be turned away in silence. */
        console.warn("Banini: the hidden field was filled with", trap.value, "- clearing it and continuing");
        if (DEBUG) rNote.textContent = "[debug] hidden field was filled with: " + trap.value;
        trap.value = "";
      }

      var name = document.getElementById("fullName");
      var email = document.getElementById("orderEmail");

      if (!lines.length){
        rNote.dataset.state = "error";
        rNote.textContent = "Add at least one jar before you reserve.";
        return;
      }
      if (name.value.trim().length < 2){
        rNote.dataset.state = "error";
        rNote.textContent = "Please give me a name to hold the jars under.";
        name.focus();
        return;
      }
      if (!EMAIL.test(email.value.trim())){
        rNote.dataset.state = "error";
        rNote.textContent = "That email does not look right. Try again.";
        email.focus();
        return;
      }
      var phone = document.getElementById("phone");
      if (phone.value.replace(/\D/g, "").length < 7){
        rNote.dataset.state = "error";
        rNote.textContent = "Please give a phone number we can reach you on.";
        phone.focus();
        return;
      }

      submitBtn.disabled = true;
      rNote.dataset.state = "ok";
      rNote.textContent = "Holding your jars.";

      rpc("create_preorder", {
        p_payload: {
          full_name: name.value.trim(),
          email: email.value.trim(),
          phone: document.getElementById("phone").value.trim(),
          city: document.getElementById("city").value.trim(),
          notes: document.getElementById("notes").value.trim(),
          items: lines.map(function(line){
            return { scent: line.scent, size: line.size, quantity: line.quantity };
          })
        }
      }).then(function(data){
        var done = document.createElement("div");
        done.className = "done";
        var h = document.createElement("h3");
        h.textContent = "Held for you.";
        var ref = document.createElement("span");
        ref.className = "ref";
        ref.textContent = data.reference;
        var p1 = document.createElement("p");
        p1.textContent = "That is your reference. Keep it somewhere, I will use it when I write to you.";
        var p2 = document.createElement("p");
        p2.textContent = lines.reduce(function(n, line){ return n + line.quantity; }, 0)
          + " jars, indicative total " + cedi(data.total_ghs)
          + ". Nothing has been charged and nothing is owed until you confirm.";
        done.appendChild(h);
        done.appendChild(ref);
        done.appendChild(p1);
        done.appendChild(p2);
        rForm.replaceWith(done);
        done.setAttribute("tabindex", "-1");
        done.focus();

        /* the reservation is placed, so the basket stops being editable */
        placed = true;
        render();
        document.getElementById("basket-h").textContent = "Reserved";
        document.querySelector(".basket-note").textContent =
          "Held under " + data.reference + ". Write to me if you want to change it.";
      }).catch(function(err){
        rNote.dataset.state = "error";
        rNote.textContent = reason(err);
        submitBtn.disabled = false;
      });
    });

    /* prices live in the database, so refresh them when we are connected */
    if (connected){
      fetch(API + "/rest/v1/sizes?select=slug,price_ghs&active=eq.true", {
        headers: { "apikey": KEY, "Authorization": "Bearer " + KEY }
      }).then(function(res){ return res.ok ? res.json() : []; }).then(function(rows){
        (rows || []).forEach(function(row){
          var input = rForm.querySelector('input[name="size"][value="' + row.slug + '"]');
          if (input) input.dataset.price = row.price_ghs;
          var tag = document.querySelector('[data-price-for="' + row.slug + '"]');
          if (tag) tag.textContent = cedi(parseFloat(row.price_ghs));
          var strip = document.querySelector('[data-size-strip="' + row.slug + '"] b');
          if (strip) strip.textContent = cedi(parseFloat(row.price_ghs));
        });
        render();
      }).catch(function(){ /* the page keeps the prices it shipped with */ });
    }
  }

  /* ---- logo ----
     Drop a wordmark at assets/logo.png and it replaces the typeset one in the
     nav and the footer. Without it the page keeps the Cormorant wordmark. */
  (function(){
    var marks = document.querySelectorAll(".wordmark");
    if (!marks.length) return;
    var src = (document.documentElement.getAttribute("data-base") || "") + "assets/logo.png";
    var probe = new Image();
    probe.onload = function(){
      marks.forEach(function(mark){
        var img = document.createElement("img");
        img.src = src;
        img.alt = "Banini Butter";
        img.className = "wordmark-img";
        var text = mark.querySelector(".wordmark-text");
        if (text) text.remove();
        mark.appendChild(img);
      });
    };
    probe.src = src;
  })();

  /* ---- media slots ----
     Drop a real asset at the path below and it replaces the illustration automatically.
     assets/hero-raw.jpg, assets/hero-jar.jpg, assets/story.jpg, assets/product.jpg, assets/texture.jpg
     A .mp4 named assets/story.mp4 takes priority in the story slot. */
  /* a page in a subfolder sets data-base="../" so these paths still resolve */
  var BASE = document.documentElement.getAttribute("data-base") || "";

  var SLOTS = {
    "hero-raw": { src: BASE + "assets/hero-raw.jpg", alt: "Raw shea nuts, some split open to show the kernel, gathered in a woven basket" },
    "hero-jar": { src: BASE + "assets/hero-jar.jpg", video: BASE + "assets/story.mp4", alt: "Banini whipped shea butter in its 50ml, 300ml and 600ml jars on a wooden table" },
    "story":    { src: BASE + "assets/story.jpg", alt: "Shea butter being whipped by hand in Tamale" },
    "product":  { src: BASE + "assets/product.jpg", alt: "Banini jars of whipped shea butter photographed on a neutral surface" },
    "blend-sunrise":       { src: BASE + "assets/blend-sunrise.jpg",       alt: "The Sunrise blend in 50ml, 300ml and 600ml jars, tagged with lemon and sweet orange" },
    "blend-warm-heritage": { src: BASE + "assets/blend-warm-heritage.jpg", alt: "The Warm Heritage blend in 50ml, 300ml and 600ml jars, tagged with cocoa" },
    "blend-nightfall":     { src: BASE + "assets/blend-nightfall.jpg",     alt: "The Nightfall blend in 50ml, 300ml and 600ml jars, tagged with lavender" },
    "reserve-header": { src: BASE + "assets/hero-jar.jpg", alt: "Banini whipped shea butter in its three jar sizes on a wooden table" }
  };

  Object.keys(SLOTS).forEach(function(name){
    var host = document.querySelector('[data-slot="' + name + '"]');
    if (!host) return;
    var cfg = SLOTS[name];

    var swap = function(el){
      var placeholder = host.querySelector("svg.media");
      if (placeholder) placeholder.remove();
      var cap = host.querySelector("figcaption");
      if (cap) cap.remove();
      host.insertBefore(el, host.firstChild);
      host.hidden = false;
    };

    var tryImage = function(){
      var probe = new Image();
      probe.onload = function(){
        var img = document.createElement("img");
        img.src = cfg.src;
        img.alt = cfg.alt;
        img.loading = "lazy";
        img.decoding = "async";
        img.className = "media";
        /* framed slots take the photograph's own shape, so nothing is cropped off.
           The hero is full bleed and keeps its crop. */
        if (host.classList.contains("media-frame") && !host.hasAttribute("data-fixed-ratio")
            && probe.naturalWidth && probe.naturalHeight){
          host.style.aspectRatio = probe.naturalWidth + " / " + probe.naturalHeight;
        }
        swap(img);
      };
      probe.src = cfg.src;
    };

    if (cfg.video){
      fetch(cfg.video, { method: "HEAD" }).then(function(res){
        if (!res.ok) throw new Error("no video");

        var v = document.createElement("video");
        v.className = "media";
        v.muted = true;
        v.loop = true;
        v.playsInline = true;
        v.setAttribute("preload", "none");
        v.setAttribute("aria-label", cfg.alt);
        if (reduce) v.controls = true;

        /* the still, if there is one, fills the frame before any frame arrives */
        var poster = new Image();
        poster.onload = function(){ v.poster = cfg.src; };
        poster.src = cfg.src;

        /* a browser that cannot decode the clip gets the still instead of a dead frame */
        v.addEventListener("error", function(){
          if (v.parentNode) v.parentNode.removeChild(v);
          tryImage();
        });

        /* the file downloads only once the section is nearly in view */
        var load = function(){
          if (v.getAttribute("src")) return;
          v.setAttribute("src", cfg.video);
          if (reduce) return;
          var playing = v.play();
          if (playing && playing.catch) playing.catch(function(){ v.controls = true; });
        };

        if (!("IntersectionObserver" in window)){
          load();
        } else {
          new IntersectionObserver(function(entries){
            entries.forEach(function(e){
              if (e.isIntersecting){
                load();
                if (!reduce && v.paused){
                  var again = v.play();
                  if (again && again.catch) again.catch(function(){ v.controls = true; });
                }
              } else if (!v.paused){
                v.pause();          /* nothing plays off screen */
              }
            });
          }, { rootMargin: "200px 0px" }).observe(v);
        }

        swap(v);
      }).catch(tryImage);
    } else {
      tryImage();
    }
  });
})();
