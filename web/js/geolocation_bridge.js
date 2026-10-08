// Jilake Speedo geolocation bridge.
//
// Wraps navigator.geolocation.watchPosition behind a tiny named API on
// window.jilakeGeo so the Dart side (WebLocationService) can start/stop the
// watch through package:web JS interop with JSON-string payloads.
//
// start(successCallbackName, errCallbackName, json):
//   - successCallbackName / errCallbackName: names of window functions the
//     Dart side registered; the bridge calls window[name](json) with a JSON
//     string payload: {latitude, longitude, speed, accuracy, heading, timestamp}.
//   - json: ignored for now, reserved for future options.
// stop(): clears the watch.
//
// jilakeGeo.speedSeen is set to true once any fix carries a non-null speed —
// used by the Dart side to know the device provides native speed values.
(function () {
  'use strict';

  var watchId = null;

  function onPosition(position) {
    var coords = position.coords;
    if (coords.speed !== null && coords.speed !== undefined) {
      window.jilakeGeo.speedSeen = true;
    }
    var payload = JSON.stringify({
      latitude: coords.latitude,
      longitude: coords.longitude,
      speed: coords.speed === undefined ? null : coords.speed,
      accuracy: coords.accuracy,
      heading: coords.heading === undefined ? null : coords.heading,
      timestamp: position.timestamp,
    });
    if (typeof window[window.jilakeGeo._successName] === 'function') {
      window[window.jilakeGeo._successName](payload);
    }
  }

  function onError(error) {
    if (typeof window[window.jilakeGeo._errorName] === 'function') {
      window[window.jilakeGeo._errorName](error);
    }
  }

  window.jilakeGeo = {
    speedSeen: false,
    _successName: null,
    _errorName: null,

    start: function (successCallbackName, errCallbackName, json) {
      if (!('geolocation' in navigator)) {
        return false;
      }
      this.stop();
      this._successName = successCallbackName;
      this._errorName = errCallbackName;
      this.speedSeen = false;
      watchId = navigator.geolocation.watchPosition(
        onPosition,
        onError,
        { enableHighAccuracy: true, maximumAge: 0, timeout: 15000 }
      );
      return true;
    },

    stop: function () {
      if (watchId !== null) {
        navigator.geolocation.clearWatch(watchId);
        watchId = null;
      }
      this._successName = null;
      this._errorName = null;
    },
  };
})();
