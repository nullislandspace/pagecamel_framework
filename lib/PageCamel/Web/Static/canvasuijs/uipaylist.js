class UIPayList {

        constructor() {
            this.paylists = [];
        }
        add(options) {
            this.paylists.push(options);
            return options;
        }
        render(ctx) {
            for (let i in this.paylists) {
                let text = this.paylists[i];

            }
        }
        onClick(x, y) {
            return;
        }
        onHover(x, y) {
            return;
        }
        onMouseDown(x, y) {
            return;
        }
        onMouseUp(x, y) {
            return;
        }
        find(name) {
         return;   
        }
    
}