/* main.js — shared UI interactions for all pages */

/* Réglage système « réduire les animations » : on le lit une fois et on
   s'y tient pour les défilements doux et les diaporamas automatiques. */
const calme = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

document.addEventListener('DOMContentLoaded', () => {

  /* ── Hamburger / mobile overlay ──────────────────────── */
  const hamburgerBtn  = document.getElementById('hamburger-btn');
  const mobileOverlay = document.getElementById('mobile-overlay');
  const overlayClose  = document.getElementById('overlay-close');

  if (hamburgerBtn && mobileOverlay) {
    function openMenu() {
      mobileOverlay.classList.add('active');
      mobileOverlay.removeAttribute('aria-hidden');
      document.body.classList.add('nav-open');
      hamburgerBtn.setAttribute('aria-expanded', 'true');
    }
    function closeMenu() {
      mobileOverlay.classList.remove('active');
      mobileOverlay.setAttribute('aria-hidden', 'true');
      document.body.classList.remove('nav-open');
      hamburgerBtn.setAttribute('aria-expanded', 'false');
    }
    hamburgerBtn.addEventListener('click', openMenu);
    if (overlayClose) overlayClose.addEventListener('click', closeMenu);
    mobileOverlay.querySelectorAll('a, .btn').forEach(el => el.addEventListener('click', closeMenu));
    document.addEventListener('keydown', e => { if (e.key === 'Escape') closeMenu(); });
  }

  /* ── Liens internes : défiler sans écrire le hash dans l'URL ──
     Sinon l'ancre reste dans l'adresse et un rechargement de la page
     ramène directement à la section au lieu du haut de la page.       */
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    const id = link.getAttribute('href').slice(1);
    if (!id) return;                     // href="#" : rien à faire
    link.addEventListener('click', e => {
      const target = document.getElementById(id);
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: calme ? 'auto' : 'smooth', block: 'start' });

      /* Le défilement seul laisse le focus sur le lien : la tabulation
         repartirait du haut de la page et le lien d'évitement ne servirait
         à rien. On donne donc le focus à la cible, en la rendant
         focalisable au besoin (le contour est retiré en CSS).            */
      if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
      target.focus({ preventScroll: true });
    });
  });

  /* ── Adresse email protégée des robots ───────────────────
     Le HTML ne contient jamais l'adresse complète : l'utilisateur et
     le domaine sont dans data-user / data-domain, et le texte affiché
     sans JS est « info [at] … ». On reconstruit le lien ici.         */
  document.querySelectorAll('.js-email').forEach(link => {
    const adresse = link.dataset.user + '@' + link.dataset.domain;
    link.href = 'mailto:' + adresse;
    (link.querySelector('.js-email-text') || link).textContent = adresse;
  });

  /* ── Vidéos qui s'enchaînent dans le même cadre ──────────
     data-sources liste les fichiers séparés par des virgules ;
     on passe au suivant à la fin de chaque clip, puis on reboucle.
     (pas d'attribut loop, sinon l'évènement « ended » ne part pas)  */
  document.querySelectorAll('video[data-sources]').forEach(video => {
    const sources = video.dataset.sources.split(',').map(s => s.trim()).filter(Boolean);
    if (sources.length < 2) return;

    let current = 0;
    video.addEventListener('ended', () => {
      current = (current + 1) % sources.length;
      video.src = sources[current];
      video.play().catch(() => {});   // autoplay refusé : on laisse tomber
    });
  });

  /* ── Lecteur maison du Bar à Croissants ──────────────────
     Les commandes du navigateur ne suivent pas la charte ; celles-ci
     sont dans le HTML et pilotées ici.                              */
  const video     = document.querySelector('.bar-video');
  const toggleBtn = document.getElementById('bar-video-toggle');
  const bar       = document.getElementById('bar-video-bar');
  const timeEl    = document.getElementById('bar-video-time');
  const iconPause = document.querySelector('.bar-video__icon--pause');
  const iconPlay  = document.querySelector('.bar-video__icon--play');

  if (video && toggleBtn) {
    /* Met le bouton d'accord avec l'état réel de la vidéo. */
    function refléter() {
      const enPause = video.paused;
      iconPause.style.display = enPause ? 'none' : '';
      iconPlay.style.display  = enPause ? '' : 'none';
      toggleBtn.setAttribute('aria-label', enPause ? 'Lecture' : 'Pause');
    }

    toggleBtn.addEventListener('click', () => {
      if (video.paused) video.play().catch(() => {});
      else              video.pause();
    });

    video.addEventListener('play',  refléter);
    video.addEventListener('pause', refléter);
    refléter();

    /* La vidéo démarre à l'arrêt pour tout le monde : on garde donc les
       commandes affichées tant qu'elle n'a pas été lancée une première
       fois, sinon la tuile passerait pour une simple photo. Au premier
       « play » on rend la main au survol. L'écoute se fait sur la vidéo
       et non sur le bouton : la lecture peut aussi partir d'ailleurs. */
    const enveloppe = video.closest('.bar-video__wrap');
    if (enveloppe) {
      enveloppe.classList.add('bar-video__wrap--ready');
      video.addEventListener('play', () => {
        enveloppe.classList.remove('bar-video__wrap--ready');
      }, { once: true });
    }

    video.addEventListener('timeupdate', () => {
      if (!video.duration) return;
      bar.style.width = (video.currentTime / video.duration * 100) + '%';
      const s = Math.floor(video.currentTime % 60);
      timeEl.textContent = Math.floor(video.currentTime / 60) + ':' + (s < 10 ? '0' : '') + s;
    });

    document.querySelector('.bar-video__progress')?.addEventListener('click', e => {
      if (!video.duration) return;
      const rect = e.currentTarget.getBoundingClientRect();
      const part = (e.clientX - rect.left) / rect.width;
      video.currentTime = Math.min(Math.max(part, 0), 1) * video.duration;
    });
  }

  /* ── Onglets : jours du menu, saisons de la confiserie ────
     Tous les panneaux sont dans le HTML (traduits, indexables) ;
     on n'affiche que l'actif. Le passage de [hidden] à visible
     relance l'animation CSS.                                      */
  document.querySelectorAll('[data-tabs]').forEach(groupe => {
    const cle     = groupe.dataset.tabs;
    const onglets = groupe.querySelectorAll('[data-' + cle + '][role="tab"]');
    const puntos  = groupe.querySelectorAll('.year__dot[data-' + cle + ']');
    const paneles = groupe.querySelectorAll('[data-' + cle + '][role="tabpanel"]');
    if (!onglets.length || !paneles.length) return;

    function activar(n) {
      onglets.forEach(o => {
        const on = o.dataset[cle] === n;
        o.classList.toggle('is-active', on);
        o.setAttribute('aria-selected', on ? 'true' : 'false');
      });
      puntos.forEach(p => p.classList.toggle('is-active', p.dataset[cle] === n));
      paneles.forEach(p => {
        const on = p.dataset[cle] === n;
        p.classList.toggle('is-active', on);
        p.hidden = !on;
      });
    }

    groupe.addEventListener('click', e => {
      const btn = e.target.closest('[data-' + cle + ']');
      if (btn && groupe.contains(btn)) activar(btn.dataset[cle]);
    });
  });

  /* ── Jour courant : on ouvre le menu du jour tout seul ────
     Le clic simulé passe par le gestionnaire d'onglets ci-dessus,
     donc l'ouverture suit exactement le même chemin qu'un vrai clic. */
  const JOURS = { 1: 'lundi', 2: 'mardi', 3: 'mercredi', 4: 'jeudi', 5: 'vendredi' };
  const jourCourant = JOURS[new Date().getDay()];
  const boutonsJour = document.querySelectorAll('.daybar__day[data-weekday]');

  if (boutonsJour.length) {
    if (jourCourant) {
      boutonsJour.forEach(btn => {
        if (btn.dataset.weekday === jourCourant) {
          btn.classList.add('daybar__day--today');
          btn.click();
        }
      });
    } else {
      const weekend = document.querySelector('.menu-weekend-msg');
      if (weekend) weekend.hidden = false;
    }
  }

  /* ── Nav scroll shadow ───────────────────────────────── */
  const siteHeader = document.getElementById('site-header');
  const topBar     = document.querySelector('.top-bar');
  if (siteHeader && topBar && 'IntersectionObserver' in window) {
    new IntersectionObserver(
      ([entry]) => siteHeader.classList.toggle('scrolled', !entry.isIntersecting),
      { threshold: 0 }
    ).observe(topBar);
  }

  /* ── Magasin slideshows (magasins.html) ─────────────── */
  document.querySelectorAll('.magasin__slideshow').forEach(show => {
    const slides = show.querySelectorAll('.magasin__slide');
    const dots   = show.querySelectorAll('.magasin__dot');
    if (slides.length < 2) return;

    let current = 0;
    let timer;

    function goTo(n) {
      slides[current].classList.remove('active');
      dots[current]?.classList.remove('active');
      current = n;
      slides[current].classList.add('active');
      dots[current]?.classList.add('active');
    }

    /* En mode « mouvement réduit » les photos ne défilent plus seules :
       les flèches et les puces restent le seul moyen de changer d'image. */
    function startTimer() {
      if (calme) return;
      timer = setInterval(() => goTo((current + 1) % slides.length), 3000);
    }

    dots.forEach((dot, i) => {
      dot.addEventListener('click', () => {
        clearInterval(timer);
        goTo(i);
        startTimer();
      });
    });

    const prevBtn = show.querySelector('.magasin__arrow--prev');
    const nextBtn = show.querySelector('.magasin__arrow--next');
    if (prevBtn) prevBtn.addEventListener('click', () => {
      clearInterval(timer);
      goTo((current - 1 + slides.length) % slides.length);
      startTimer();
    });
    if (nextBtn) nextBtn.addEventListener('click', () => {
      clearInterval(timer);
      goTo((current + 1) % slides.length);
      startTimer();
    });

    show.addEventListener('mouseenter', () => clearInterval(timer));
    show.addEventListener('mouseleave', startTimer);

    startTimer();
  });

  /* ── Diaporama du hero (accueil et Tea-room) ─────────── */
  const slides = document.querySelectorAll('.hero__slide');
  const dots   = document.querySelectorAll('.hero__dot');
  if (slides.length > 1) {
    let current = 0;

    function goToSlide(n) {
      slides[current].classList.remove('active');
      dots[current]?.classList.remove('active');
      current = n;
      slides[current].classList.add('active');
      dots[current]?.classList.add('active');
    }

    /* Init first slide */
    slides[0].classList.add('active');
    dots[0]?.classList.add('active');

    /* Défilement automatique toutes les 4 secondes — sauf si le système
       demande moins d'animations : la première photo reste alors en place,
       les puces permettant toujours de passer aux suivantes. */
    const relancer = () => calme
      ? null
      : setInterval(() => goToSlide((current + 1) % slides.length), 4000);

    let timer = relancer();

    dots.forEach((dot, i) => {
      dot.addEventListener('click', () => {
        clearInterval(timer);
        goToSlide(i);
        timer = relancer();
      });
    });
  } else if (slides.length === 1) {
    slides[0].classList.add('active');
  }

  /* ── Apparition au défilement (Actualités) ───────────────
     Les éléments ne sont masqués qu'ici, en JS : sans script,
     ou si l'utilisateur demande moins d'animations, le contenu
     reste visible et indexable.                                  */
  const reveals = document.querySelectorAll('.js-reveal');

  if (reveals.length && !calme && 'IntersectionObserver' in window) {
    reveals.forEach(el => el.classList.add('is-revealable'));

    const observer = new IntersectionObserver((entries, obs) => {
      /* On décale l'entrée des éléments visibles ensemble : la
         rangée se révèle en cascade plutôt que d'un seul bloc. */
      entries
        .filter(entry => entry.isIntersecting)
        .forEach((entry, i) => {
          const el    = entry.target;
          const delai = i * 90;
          el.style.setProperty('--reveal-delay', delai + 'ms');
          el.classList.add('is-revealed');
          obs.unobserve(el);

          /* Une fois l'apparition terminée on retire les classes :
             leur « transform » masquerait sinon l'élévation au survol
             des cartes, définie plus haut dans la feuille de style.  */
          const finir = () => {
            el.classList.remove('is-revealable', 'is-revealed');
            el.style.removeProperty('--reveal-delay');
          };
          el.addEventListener('transitionend', finir, { once: true });
          setTimeout(finir, delai + 900);   // filet de sécurité
        });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });

    reveals.forEach(el => observer.observe(el));
  }

});
