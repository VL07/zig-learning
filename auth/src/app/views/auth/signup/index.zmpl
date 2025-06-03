@if ($.stage == 0)
    <form method="post">
        <fieldset>
            <legend>Register</legend>
            <input type="email" name="email" placeholder="Email">
            <button type="submit">Register</button>
        </fieldset>
    </form>
@else if ($.stage == 1)
    <form method="post">
        <fieldset>
            <legend>Register</legend>
            <input type="email" name="email" value="{{.email}}" disabled>
            <input type="text" name="username" placeholder="Username">
            <input type="password" name="password" placeholder="Password">
            <button type="submit">Register</button>
        </fieldset>
    </form>
@end