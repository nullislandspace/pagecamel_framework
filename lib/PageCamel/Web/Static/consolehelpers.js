console.image = function(url) {
  const image = new Image();
  image.src = url;
  image.onload = function() {
    var style = [
      'font-size: 1px;',
      'padding: ' + this.height + 'px ' + this.width + 'px;',
      'background: url('+ url +') no-repeat;',
      'background-size: contain;'
     ].join(' ');
     console.log('%c ', style);
  };
};
