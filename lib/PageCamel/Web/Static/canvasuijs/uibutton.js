/*
=pod

=head1 UIButton

=head2 C<.add({options})>

=over

returns object C<options>

=back

=head3 required options

=over

C<
x: number, y: number, width: number, height: number, 
background: ['#000000', '#000000'], callback: function, foreground: '#000000'
>

C<x> and C<y> are the top left corner positions of the button.

C<width> and C<height> are the width and height of the button.

C<background> is an array of two colors. One color is required for a solid color button, and the other is required for a gradient button.
Possible values are: hexadecimal color codes, rgb color codes and rgba color codes.

C<callback> is the function to call when the button is clicked.

C<foreground> is the color of the text on the button. Possible values are: hexadecimal color codes, rgb color codes and rgba color codes. 

=back

=head3 optional options

=over

C<
border_width: number, border_radius: number, font_size: number, 
hover_border: '#000000', gradient_type: 'horizontal' | 'vertical',
border: '#000000', align: 'left' | 'right' | 'center', displaytext: string, accept_keycode: [keycode1, keycode2, ...],
select_file: boolean
>

C<border_width> is the width of the border.

C<border_radius> is the radius of the border.

C<font_size> is the size of the text on the button.

C<hover_border> is the color of the border when the mouse is hovering over the button.

C<gradient_type> is the type of gradient to use. Possible values are: 'horizontal', 'vertical'. Default is 'vertical'.

C<border> is the color of the border.

C<align> is the alignment of the text on the button. Possible values are: 'left', 'right', 'center'.

C<displaytext> is the text to display on the button.

C<accept_keycode> is an array of keycodes that can be used to click the button.

C<select_file> is a boolean that determines if the user can select a file.

=back
        
=head2 C<.render(ctx)>

=over

draws button on canvas

C<ctx> is the canvas context to draw on

=back

=head2 C<.onFileInput(input)>

=over

called when a file is selected

C<input> is the file input element

=back

=head2 C<.onClick(x, y)>

=over

Click event handler.

C<x> is the x coordinate of the mouse click event

C<y> is the y coordinate of the mouse click event

=back
  
=head2 C<.onMouseDown(x, y)>

=over

Mouse down event handler.

C<x> is the x coordinate of the mouse down event

C<y> is the y coordinate of the mouse down event

=back

=head2 C<.onMouseMove(x, y)>

=over

Mouse move event handler.

C<x> is the x coordinate of the mouse move event

C<y> is the y coordinate of the mouse move event

=back

=head2 C<.find(name)>

=over

finds a button by name

returns the button object (options object) if found, undefined otherwise

=back
        
=head2 C<.clear()>

=over

clears the buttons

=back

=head2 C<.onKeyDown(e)>

=over
        
called when a key is pressed.

Only triggers a callback if the pressed key is in the C<accept_keycode> array.

e is the key event

=back

=cut
*/

class UIButton {
    constructor(canvas) {
        this.hovering_on = null;
        this.buttons = [];
        this.mouse_down_on = null;
    }

    add(options) {
        options.active = true;
        options.setActive = (active) => {
            options.active = active;
        }
        if (!options.grd_type) {
            options.grd_type = 'vertical';
        }
        this.buttons.push(options);
        return options;
    }
    render(ctx) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button.active) {
                ctx.lineWidth = button.border_width;
                ctx.font = button.font_size + 'px Everson Mono';
                if (i == this.hovering_on) {
                    ctx.strokeStyle = button.hover_border;
                }
                else {
                    ctx.strokeStyle = button.border;
                }
                var grd;
                if (button.grd_type == 'horizontal') {
                    grd = ctx.createLinearGradient(button.x, button.y, button.x + button.width, button.y);
                }
                else if (button.grd_type == 'vertical') {
                    grd = ctx.createLinearGradient(button.x, button.y, button.x, button.y + button.height);
                }
                if (button.grd_type) {
                    var step_size = 1 / button.background.length;
                    if (i == this.mouse_down_on) {
                        ctx.fillStyle = button.background[button.background.length - 1];
                    }
                    else {
                        for (var j in button.background) {
                            grd.addColorStop(step_size * j, button.background[j]);
                            ctx.fillStyle = grd;
                        }
                    }
                }
                if (button.background.length == 1) {
                    ctx.fillStyle = button.background[0];
                }
                if (!button.border_radius) {
                    ctx.fillRect(button.x, button.y, button.width, button.height);
                    ctx.strokeRect(button.x, button.y, button.width, button.height);
                } else {
                    roundRect(ctx, button.x, button.y, button.width, button.height, button.border_radius, button.border_width);
                }
                ctx.fillStyle = button.foreground;
                ctx.strokeStyle = button.foreground;
                if (button.displaytext) {
                    if (!button.displaytext.includes("\n")) {
                        var text_width = ctx.measureText(button.displaytext).width;
                        if (button.align == 'right') {
                            //align text right
                            ctx.fillText(button.displaytext, button.x + button.width - text_width - 8, button.y + (button.height / 2) + button.font_size / 3.3);
                        }
                        else if (button.align == 'left') {
                            //align text left
                            ctx.fillText(button.displaytext, button.x + 8, button.y + (button.height / 2) + button.font_size / 3.3);
                        }
                        else {
                            //align text center
                            ctx.fillText(button.displaytext, button.x + (button.width - text_width) / 2, button.y + (button.height / 2) + button.font_size / 3.3);
                        }

                    } else {
                        var blines = button.displaytext.split("\n");
                        var yoffs = button.y + ((button.height / 2) - (9 * (blines.length - 1)));
                        var j;
                        for (j = 0; j < blines.length; j++) {
                            blines[j].replace("\n", '');
                            ctx.fillText(blines[j], button.x + 8, yoffs);
                            yoffs = yoffs + 18;
                        }
                    }
                }
            }
        }
    }
    onFileInput(input) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button.select_file === true && button.selector_opened == true) {
                button.selector_opened = false;
                var callback_button = button;
                var fr = new FileReader();
                fr.onload = function () {
                    var bgimage = fr.result;
                    
                    //check if image is valid
                    var img = new Image();
                    img.onload = function () {
                        callback_button.callback(bgimage); //call callback if image is valid
                    }
                    img.onerror = function () {
                        return; //invalid image
                    };
                    img.src = bgimage;
                    input.value = ""; //prevents caching of the image
                }
                fr.readAsDataURL(input.files[0]);
            }
        }
    }
    onClick(x, y) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button && button.active) {
                var startx = button.x;
                var starty = button.y;
                var endx = startx + button.width;
                var endy = starty + button.height;
                button.selector_opened = false;
                if (x >= startx && x <= endx && y >= starty && y <= endy && this.mouse_down_on == i) {
                    if (button.select_file === true) {
                        button.selector_opened = true;
                        $("#upload").trigger('click');
                    }
                    else {
                        button.callback(button.callbackData);
                    }
                    triggerRepaint();
                }
            }
        }
        this.mouse_down_on = null;
    }
    onMouseUp(x, y) {
        return;
    }
    onMouseDown(x, y) {

        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button.active) {
                var startx = button.x;
                var starty = button.y;
                var endx = startx + button.width;
                var endy = starty + button.height;
                if (x >= startx && x <= endx && y >= starty && y <= endy) {
                    this.mouse_down_on = i;
                    triggerRepaint();
                    return;
                }
            }
        }
        this.mouse_down_on = -1;
        return;
    }
    onMouseMove(x, y) {

        for (var i in this.buttons) {
            var button = this.buttons[i];
            var startx = button.x;
            var starty = button.y;
            var endx = startx + button.width;
            var endy = starty + button.height;
            if (x >= startx && x <= endx && y >= starty && y <= endy && (this.mouse_down_on == null || this.mouse_down_on == i)) {
                this.hovering_on = i;
                triggerRepaint();
                return;
            }
        }
        if (this.hovering_on != null) {
            triggerRepaint();
        }
        this.hovering_on = null;
        return;
    }
    find(name) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            if (button.name == name) {
                return button;
            }
        }
    }
    clear() {
        this.mouse_down_on = null;
        this.hovering_on = null;
        this.buttons = [];
    }
    onKeyDown(e) {
        for (var i in this.buttons) {
            var button = this.buttons[i];
            for (var j in button.accept_keycode) {
                if (button.accept_keycode[j] == e.keyCode) {
                    e.preventDefault();
                    button.callback(button.callbackData);
                    triggerRepaint();
                }
            }
        }
    }
}
canvasuijs.addLateType('Button', UIButton);
