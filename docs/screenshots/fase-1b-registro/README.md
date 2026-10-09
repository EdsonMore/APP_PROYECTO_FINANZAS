# Capturas: registro de gasto e ingreso (fase-1b)

Emulador Android API 37, 1080×2400 a 420 dpi. El Home todavía no existe:
las hojas se abrieron desde un punto de entrada temporal que no está en el repo.

- `registro-gasto-nota-claro.png`: el teclado propio se oculta con la nota
  activa. El emulador muestra la barra flotante de Gboard (modo teclado
  físico), no el teclado completo. El caso "Guardar sobre el teclado del
  sistema" está cubierto por un test de widget con 300 dp de teclado simulado.
- `registro-gasto-guardando-claro.png`: el insert se retrasó 4 s a propósito
  para poder capturar el spinner. El guardado real tarda milisegundos.
